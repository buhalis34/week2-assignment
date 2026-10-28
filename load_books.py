"""Load books from books.csv into library.db.

Usage:
    python3 load_books.py            # loads the first 25 books
    python3 load_books.py --limit 100

For each book this adds a row to books, its authors to authors (each person
stored once), one row per book-author pair to book_authors, and one physical
copy to book_copies. books.csv is only read, never changed.

Books already in the database (same book_id) are skipped, so running the
script twice does not create duplicates.
"""

import argparse
import csv
import sqlite3
from pathlib import Path

HERE = Path(__file__).resolve().parent


def clean_isbn(raw):
    """Return a valid 10-character ISBN, or None.

    The CSV stored ISBNs as numbers, so leading zeros were lost
    (0061120081 became 61120081). Pad them back, then check the ISBN-10
    check digit so a bad value is stored as NULL instead of a wrong ISBN.
    """
    isbn = raw.strip().upper()
    if not isbn:
        return None
    isbn = isbn.zfill(10)
    if len(isbn) != 10 or not isbn[:9].isdigit() or not (isbn[9].isdigit() or isbn[9] == "X"):
        return None
    digits = [int(c) for c in isbn[:9]] + [10 if isbn[9] == "X" else int(isbn[9])]
    if sum((10 - i) * d for i, d in enumerate(digits)) % 11 != 0:
        return None
    return isbn


def clean_year(raw):
    """'2008.0' -> 2008; blank -> None."""
    raw = raw.strip()
    return int(float(raw)) if raw else None


def split_authors(raw):
    """'J.K. Rowling, Mary GrandPré' -> ['J.K. Rowling', 'Mary GrandPré'] (order kept, no repeats)."""
    names = []
    for name in raw.split(","):
        name = " ".join(name.split())
        if name and name not in names:
            names.append(name)
    return names


def get_or_create_author(cur, name):
    row = cur.execute("SELECT author_id FROM authors WHERE name = ?", (name,)).fetchone()
    if row:
        return row[0]
    cur.execute("INSERT INTO authors (name) VALUES (?)", (name,))
    return cur.lastrowid


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--limit", type=int, default=25, help="number of books to load from the top of the CSV")
    parser.add_argument("--csv", type=Path, default=HERE / "books.csv")
    parser.add_argument("--db", type=Path, default=HERE / "library.db")
    args = parser.parse_args()

    conn = sqlite3.connect(args.db)
    conn.execute("PRAGMA foreign_keys = ON")
    cur = conn.cursor()
    added = skipped = 0

    # One transaction: if anything fails, nothing is saved.
    with conn, open(args.csv, newline="", encoding="utf-8") as f:
        for i, row in enumerate(csv.DictReader(f)):
            if i >= args.limit:
                break
            book_id = int(row["book_id"])
            if cur.execute("SELECT 1 FROM books WHERE book_id = ?", (book_id,)).fetchone():
                skipped += 1
                continue

            cur.execute(
                "INSERT INTO books (book_id, title, publication_year, isbn) VALUES (?, ?, ?, ?)",
                (book_id, " ".join(row["title"].split()), clean_year(row["original_publication_year"]),
                 clean_isbn(row["isbn"])),
            )
            for order, name in enumerate(split_authors(row["authors"]), start=1):
                cur.execute(
                    "INSERT INTO book_authors (book_id, author_id, author_order) VALUES (?, ?, ?)",
                    (book_id, get_or_create_author(cur, name), order),
                )
            cur.execute("INSERT INTO book_copies (book_id) VALUES (?)", (book_id,))
            added += 1

    print(f"Added {added} books, skipped {skipped} already in the database.")
    conn.close()


if __name__ == "__main__":
    main()
