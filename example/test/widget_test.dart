import 'package:flutter_test/flutter_test.dart';

import 'package:gatewire_example/main.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const GateWireExampleApp());
    expect(find.text('GateWire SDK Demo'), findsOneWidget);
  });
}
