import 'package:flutter_test/flutter_test.dart';
import 'package:fyp_test/main.dart';

void main() {
  testWidgets('App loads home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const NotebookApp());
    expect(find.text('My Notebooks'), findsOneWidget);
  });
}