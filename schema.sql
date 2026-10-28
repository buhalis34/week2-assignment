-- schema.sql
-- Library database for the MSAI-5523 Module 2 assignment.
--
-- Build the database with:
--     sqlite3 library.db < schema.sql
--
-- Dates are stored as TEXT in ISO format (YYYY-MM-DD) so they sort and
-- compare correctly and work with SQLite's date() functions.
--
-- SQLite only enforces foreign keys when they are turned on, and the setting
-- lasts for one connection. Run this at the start of every session:
--     PRAGMA foreign_keys = ON;

PRAGMA foreign_keys = ON;

------------------------------------------------------------------------------
-- Authors: one row per person, no matter how many books they wrote.
------------------------------------------------------------------------------
CREATE TABLE authors (
    author_id INTEGER PRIMARY KEY,
    name      TEXT NOT NULL UNIQUE CHECK (trim(name) <> '')
);

------------------------------------------------------------------------------
-- Books: one row per title (the "work"), not per physical copy.
------------------------------------------------------------------------------
CREATE TABLE books (
    book_id          INTEGER PRIMARY KEY,
    title            TEXT NOT NULL CHECK (trim(title) <> ''),
    publication_year INTEGER,
    -- ISBN is TEXT so leading zeros and a trailing 'X' are kept.
    -- It can be NULL because some older books have no ISBN.
    isbn             TEXT UNIQUE CHECK (isbn IS NULL OR length(isbn) IN (10, 13))
);

------------------------------------------------------------------------------
-- Book_authors: links books and authors (many-to-many).
-- A book can have several authors; an author can have several books.
------------------------------------------------------------------------------
CREATE TABLE book_authors (
    book_id      INTEGER NOT NULL REFERENCES books (book_id) ON DELETE CASCADE,
    author_id    INTEGER NOT NULL REFERENCES authors (author_id) ON DELETE RESTRICT,
    -- 1 = first-listed author, 2 = second, and so on.
    author_order INTEGER NOT NULL DEFAULT 1 CHECK (author_order >= 1),
    PRIMARY KEY (book_id, author_id),
    UNIQUE (book_id, author_order)
);

CREATE INDEX idx_book_authors_author ON book_authors (author_id);

------------------------------------------------------------------------------
-- Book_copies: one row per physical item on the shelf.
-- Whether a copy is on loan is worked out from borrowings, not stored here,
-- so the two can never disagree. condition_status covers everything else.
------------------------------------------------------------------------------
CREATE TABLE book_copies (
    copy_id          INTEGER PRIMARY KEY,
    book_id          INTEGER NOT NULL REFERENCES books (book_id) ON DELETE RESTRICT,
    barcode          TEXT UNIQUE,
    acquired_date    TEXT CHECK (acquired_date IS NULL OR date(acquired_date) IS acquired_date),
    condition_status TEXT NOT NULL DEFAULT 'in_circulation'
        CHECK (condition_status IN ('in_circulation', 'damaged', 'lost', 'withdrawn'))
);

CREATE INDEX idx_book_copies_book ON book_copies (book_id);

------------------------------------------------------------------------------
-- Members: people who can borrow books.
------------------------------------------------------------------------------
CREATE TABLE members (
    member_id   INTEGER PRIMARY KEY,
    name        TEXT NOT NULL CHECK (trim(name) <> ''),
    email       TEXT NOT NULL UNIQUE COLLATE NOCASE CHECK (email LIKE '_%@_%._%'),
    joined_date TEXT NOT NULL DEFAULT (date('now', 'localtime'))
        CHECK (date(joined_date) IS joined_date)
);

------------------------------------------------------------------------------
-- Borrowings: one row each time a member checks out a copy.
-- return_date stays NULL until the copy comes back.
------------------------------------------------------------------------------
CREATE TABLE borrowings (
    borrowing_id  INTEGER PRIMARY KEY,
    copy_id       INTEGER NOT NULL REFERENCES book_copies (copy_id) ON DELETE RESTRICT,
    member_id     INTEGER NOT NULL REFERENCES members (member_id) ON DELETE RESTRICT,
    checkout_date TEXT NOT NULL DEFAULT (date('now', 'localtime'))
        CHECK (date(checkout_date) IS checkout_date),
    due_date      TEXT NOT NULL
        CHECK (date(due_date) IS due_date AND due_date >= checkout_date),
    return_date   TEXT
        CHECK (return_date IS NULL
               OR (date(return_date) IS return_date AND return_date >= checkout_date))
);

CREATE INDEX idx_borrowings_member ON borrowings (member_id);

-- A copy can only be out with one member at a time:
-- at most one borrowing per copy may have no return date.
CREATE UNIQUE INDEX idx_borrowings_one_open_per_copy
    ON borrowings (copy_id) WHERE return_date IS NULL;

-- Only copies in circulation can be checked out.
CREATE TRIGGER trg_borrowings_copy_in_circulation
BEFORE INSERT ON borrowings
WHEN (SELECT condition_status FROM book_copies WHERE copy_id = NEW.copy_id)
     <> 'in_circulation'
BEGIN
    SELECT RAISE(ABORT, 'This copy is not in circulation and cannot be borrowed');
END;

------------------------------------------------------------------------------
-- Views: availability is calculated from the data above, so it is always
-- up to date. "Overdue" uses today's date each time you query it.
------------------------------------------------------------------------------

-- Status of every physical copy:
-- available, checked_out, overdue, damaged, lost, or withdrawn.
CREATE VIEW copy_status AS
SELECT
    c.copy_id,
    c.book_id,
    b.title,
    c.barcode,
    br.borrowing_id,
    br.member_id,
    br.checkout_date,
    br.due_date,
    CASE
        WHEN c.condition_status <> 'in_circulation' THEN c.condition_status
        WHEN br.borrowing_id IS NULL THEN 'available'
        WHEN br.due_date < date('now', 'localtime') THEN 'overdue'
        ELSE 'checked_out'
    END AS status
FROM book_copies AS c
JOIN books AS b ON b.book_id = c.book_id
LEFT JOIN borrowings AS br
    ON br.copy_id = c.copy_id AND br.return_date IS NULL;

-- Availability of every book (title), counting its copies.
CREATE VIEW book_availability AS
SELECT
    b.book_id,
    b.title,
    COUNT(cs.copy_id)                                       AS total_copies,
    COALESCE(SUM(cs.status = 'available'), 0)               AS available_copies,
    COALESCE(SUM(cs.status = 'checked_out'), 0)             AS checked_out_copies,
    COALESCE(SUM(cs.status = 'overdue'), 0)                 AS overdue_copies,
    CASE
        WHEN COUNT(cs.copy_id) = 0 THEN 'no_copies'
        WHEN SUM(cs.status = 'available') > 0 THEN 'available'
        WHEN SUM(cs.status IN ('checked_out', 'overdue')) > 0 THEN 'all_checked_out'
        ELSE 'unavailable'
    END AS availability
FROM books AS b
LEFT JOIN copy_status AS cs ON cs.book_id = b.book_id
GROUP BY b.book_id, b.title;

-- Loans that are past due and not yet returned.
CREATE VIEW overdue_borrowings AS
SELECT
    br.borrowing_id,
    m.member_id,
    m.name  AS member_name,
    m.email AS member_email,
    c.copy_id,
    b.title,
    br.checkout_date,
    br.due_date,
    CAST(julianday(date('now', 'localtime')) - julianday(br.due_date) AS INTEGER)
        AS days_overdue
FROM borrowings AS br
JOIN members     AS m ON m.member_id = br.member_id
JOIN book_copies AS c ON c.copy_id   = br.copy_id
JOIN books       AS b ON b.book_id   = c.book_id
WHERE br.return_date IS NULL
  AND br.due_date < date('now', 'localtime');
