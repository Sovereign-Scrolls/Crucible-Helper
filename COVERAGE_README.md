# Flutter Code Coverage Guide

## What is Code Coverage?

Code coverage is a metric that measures how much of your source code is executed when your tests run. It helps you understand which parts of your code are tested and which parts might need additional testing.

## Types of Code Coverage

### 1. **Line Coverage**
- Measures which lines of code are executed during testing
- Shows the percentage of lines that were run at least once
- Example: If you have 100 lines of code and 80 are executed during tests, you have 80% line coverage

### 2. **Branch Coverage**
- Measures which branches in conditional statements (if/else, switch) are executed
- Ensures both true and false paths are tested
- Example: Testing both the success and error cases of a function

### 3. **Function Coverage**
- Measures which functions/methods are called during testing
- Shows which functions remain untested
- Example: Ensuring all public methods in a class are tested

### 4. **Statement Coverage**
- Similar to line coverage but focuses on executable statements
- Excludes comments and blank lines
- More precise than line coverage

## How to Generate Code Coverage

### Quick Start
```bash
# Run tests with coverage
flutter test --coverage

# Generate HTML report
genhtml coverage/lcov.info -o coverage/html

# Open the report
open coverage/html/index.html
```

### Using the Coverage Script
```bash
# Make the script executable (if not already done)
chmod +x coverage.sh

# Run the coverage script
./coverage.sh
```

## Understanding Coverage Reports

### Coverage Metrics
- **Lines**: Number of lines executed vs total lines
- **Functions**: Number of functions called vs total functions
- **Branches**: Number of branches executed vs total branches

### Color Coding in HTML Reports
- **Green**: Fully covered code
- **Red**: Uncovered code
- **Yellow**: Partially covered code

### What to Look For
1. **Low Coverage Areas**: Files or functions with < 80% coverage
2. **Untested Branches**: Conditional statements not fully tested
3. **Error Paths**: Exception handling and error cases
4. **Edge Cases**: Boundary conditions and unusual inputs

## Best Practices for Code Coverage

### 1. **Aim for High Coverage (80%+)**
- Focus on critical business logic
- Test error handling paths
- Cover edge cases and boundary conditions

### 2. **Test Different Scenarios**
```dart
// Example: Testing multiple scenarios
test('Character creation with different data', () {
  // Test valid data
  testValidCharacterCreation();
  
  // Test invalid data
  testInvalidCharacterCreation();
  
  // Test edge cases
  testEdgeCaseCharacterCreation();
});
```

### 3. **Mock External Dependencies**
```dart
// Example: Mocking Firebase for testing
test('Character fetch from Firebase', () async {
  // Mock Firebase response
  when(mockFirebase.getData()).thenAnswer((_) async => mockData);
  
  // Test the function
  final character = await fetchCharacter();
  
  // Verify results
  expect(character, isNotNull);
});
```

### 4. **Test Widget Interactions**
```dart
// Example: Testing widget interactions
testWidgets('Login button triggers authentication', (tester) async {
  await tester.pumpWidget(LoginPage());
  
  // Find and tap the login button
  await tester.tap(find.byType(ElevatedButton));
  await tester.pump();
  
  // Verify the expected behavior
  expect(find.text('Loading...'), findsOneWidget);
});
```

## Coverage Configuration

### Exclude Files from Coverage
Create a `.lcovrc` file in your project root:
```
# Exclude generated files
LCOV_EXCL_LINE = "// coverage:ignore-line"
LCOV_EXCL_START = "// coverage:ignore-start"
LCOV_EXCL_STOP = "// coverage:ignore-stop"
```

### Ignore Specific Lines
```dart
// coverage:ignore-line
final debugPrint = print; // This line won't be counted

// coverage:ignore-start
// This entire block won't be counted
void debugFunction() {
  print('Debug info');
}
// coverage:ignore-stop
```

## Continuous Integration

### GitHub Actions Example
```yaml
name: Test Coverage
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.16.0'
      - run: flutter pub get
      - run: flutter test --coverage
      - run: genhtml coverage/lcov.info -o coverage/html
      - uses: actions/upload-artifact@v2
        with:
          name: coverage-report
          path: coverage/html
```

## Common Issues and Solutions

### 1. **Low Coverage on Generated Code**
- Exclude generated files from coverage
- Focus on testing your business logic

### 2. **Difficult to Test UI Code**
- Extract business logic from widgets
- Use widget tests for UI interactions
- Mock dependencies

### 3. **External Dependencies**
- Use mocks for external services
- Test integration points separately
- Use dependency injection for testability

## Tools and Extensions

### VS Code Extensions
- **Coverage Gutters**: Shows coverage in the editor
- **Flutter Test Explorer**: Better test organization

### Command Line Tools
- **lcov**: Generate HTML reports
- **genhtml**: Convert LCOV to HTML

## Example Coverage Report Structure

```
coverage/
├── lcov.info          # Raw coverage data
└── html/
    ├── index.html     # Main coverage report
    ├── css/           # Styling
    └── js/            # JavaScript for interactivity
```

## Next Steps

1. **Run your first coverage report**: `./coverage.sh`
2. **Review the HTML report**: Look for red (uncovered) areas
3. **Write tests for uncovered code**: Focus on critical paths first
4. **Set coverage goals**: Aim for 80%+ coverage
5. **Integrate with CI/CD**: Automate coverage reporting

## Resources

- [Flutter Testing Documentation](https://docs.flutter.dev/testing)
- [LCOV Documentation](http://ltp.sourceforge.net/coverage/lcov.php)
- [Code Coverage Best Practices](https://martinfowler.com/bliki/TestCoverage.html) 