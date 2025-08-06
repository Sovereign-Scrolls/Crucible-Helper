#!/bin/bash

echo "🧪 Running Flutter tests with coverage..."
flutter test --coverage

echo "📊 Generating HTML coverage report..."
genhtml coverage/lcov.info -o coverage/html

echo "🌐 Opening coverage report in browser..."
if command -v xdg-open &> /dev/null; then
    xdg-open coverage/html/index.html
elif command -v open &> /dev/null; then
    open coverage/html/index.html
else
    echo "📁 Coverage report generated at: coverage/html/index.html"
    echo "Please open this file in your browser to view the coverage report."
fi

echo "✅ Coverage report generation complete!" 