import sqlite3
from typing import List, Dict, Optional

def init_db():
    """Initialize the SQLite database"""
    conn = sqlite3.connect('stock_portfolio.db')
    cursor = conn.cursor()
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS portfolio (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ticker TEXT NOT NULL,
            buy_price REAL NOT NULL,
            quantity REAL NOT NULL,
            date TEXT NOT NULL
        )
    ''')
    conn.commit()
    conn.close()
    print("Database initialized successfully")
    
    # Initialize budget table
    init_budget_table()

def add_position(position: Dict) -> None:
    """Add a position to the portfolio"""
    conn = sqlite3.connect('stock_portfolio.db')
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO portfolio (ticker, buy_price, quantity, date)
        VALUES (?, ?, ?, ?)
    ''', (position['ticker'], position['buy_price'], position['quantity'], position['date']))
    conn.commit()
    conn.close()

def get_all_positions() -> List[Dict]:
    """Get all positions from the portfolio"""
    conn = sqlite3.connect('stock_portfolio.db')
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM portfolio')
    rows = cursor.fetchall()
    conn.close()
    
    positions = []
    for row in rows:
        positions.append({
            'id': row[0],
            'ticker': row[1],
            'buy_price': row[2],
            'quantity': row[3],
            'date': row[4]
        })
    return positions

def delete_position(position_id: int) -> None:
    """Delete a position from the portfolio"""
    conn = sqlite3.connect('stock_portfolio.db')
    cursor = conn.cursor()
    cursor.execute('DELETE FROM portfolio WHERE id = ?', (position_id,))
    conn.commit()
    conn.close()

def update_position(position_id: int, position: Dict) -> None:
    """Update a position in the portfolio"""
    conn = sqlite3.connect('stock_portfolio.db')
    cursor = conn.cursor()
    cursor.execute('''
        UPDATE portfolio 
        SET ticker = ?, buy_price = ?, quantity = ?, date = ?
        WHERE id = ?
    ''', (position['ticker'], position['buy_price'], position['quantity'], position['date'], position_id))
    conn.commit()
    conn.close()

def init_budget_table():
    """Initialize the budget table"""
    conn = sqlite3.connect('stock_portfolio.db')
    cursor = conn.cursor()
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS budget (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            amount REAL NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    conn.commit()
    conn.close()

def set_budget(amount: float) -> None:
    """Set the budget amount"""
    conn = sqlite3.connect('stock_portfolio.db')
    cursor = conn.cursor()
    cursor.execute('DELETE FROM budget')  # Clear existing budget
    cursor.execute('INSERT INTO budget (amount) VALUES (?)', (amount,))
    conn.commit()
    conn.close()

def get_budget() -> Optional[Dict]:
    """Get the current budget"""
    conn = sqlite3.connect('stock_portfolio.db')
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM budget ORDER BY id DESC LIMIT 1')
    row = cursor.fetchone()
    conn.close()
    
    if row:
        return {
            'id': row[0],
            'amount': row[1],
            'created_at': row[2]
        }
    return None