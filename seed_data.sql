-- seed_data.sql
-- Fictional members and borrowings for testing library.db.
-- Dates assume today is 2026-10-28. Loans are 14 days long.
--
-- Run once, after load_books.py:
--     sqlite3 -bail library.db < seed_data.sql
-- If any row fails (for example, if it was already run), nothing is saved.

PRAGMA foreign_keys = ON;

BEGIN;

-- Member 5 (Ethan) has never borrowed a book.
INSERT INTO members (member_id, name, email, joined_date) VALUES
    (1, 'Alice Moreno', 'alice.moreno@example.com', '2026-06-02'),
    (2, 'Ben Okafor',   'ben.okafor@example.com',   '2026-06-15'),
    (3, 'Chloe Park',   'chloe.park@example.com',   '2026-07-08'),
    (4, 'David Novak',  'david.novak@example.com',  '2026-08-21'),
    (5, 'Ethan Reyes',  'ethan.reyes@example.com',  '2026-10-22');

-- Each copy_id below is the single copy of the matching book_id.
INSERT INTO borrowings (borrowing_id, copy_id, member_id, checkout_date, due_date, return_date) VALUES
    -- Returned
    ( 1,  1, 1, '2026-08-03', '2026-08-17', '2026-08-15'),  -- The Hunger Games
    ( 2,  4, 2, '2026-08-20', '2026-09-03', '2026-09-05'),  -- To Kill a Mockingbird (returned 2 days late)
    ( 3,  1, 2, '2026-09-01', '2026-09-15', '2026-09-12'),  -- The Hunger Games again, after loan 1 came back
    ( 4,  7, 3, '2026-09-10', '2026-09-24', '2026-09-22'),  -- The Hobbit
    ( 5, 13, 4, '2026-09-28', '2026-10-12', '2026-10-10'),  -- 1984
    -- Checked out, not yet due
    ( 6,  4, 4, '2026-10-15', '2026-10-29', NULL),          -- To Kill a Mockingbird (due tomorrow)
    ( 7,  2, 1, '2026-10-20', '2026-11-03', NULL),          -- Harry Potter and the Sorcerer's Stone
    ( 8, 10, 3, '2026-10-25', '2026-11-08', NULL),          -- Pride and Prejudice
    -- Checked out and overdue
    ( 9, 18, 2, '2026-09-30', '2026-10-14', NULL),          -- Harry Potter and the Prisoner of Azkaban
    (10, 22, 1, '2026-10-05', '2026-10-19', NULL);          -- The Lovely Bones

COMMIT;
