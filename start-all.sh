#!/bin/bash

# Start both frontend and backend together

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "Starting StockSense (Frontend + Backend)..."

# Kill any existing processes on port 8000
lsof -ti:8000 | xargs kill -9 2>/dev/null

# Add Flutter to PATH
export PATH="$PATH:$HOME/flutter/bin"

# Activate virtual environment and start backend in background
source venv/bin/activate
pip install -r requirements.txt > /dev/null 2>&1
python main.py &
BACKEND_PID=$!

echo "Backend started (PID: $BACKEND_PID)"
echo "Backend URL: http://127.0.0.1:8000"

# Wait for backend to be ready
echo "Waiting for backend to start..."
sleep 3

# Start Flutter app
cd flutter_app
echo "Starting Flutter app..."
flutter run -d chrome

# Cleanup when Flutter app is closed
echo "Stopping backend..."
kill $BACKEND_PID 2>/dev/null
