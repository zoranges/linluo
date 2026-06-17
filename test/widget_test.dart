import 'package:film_watermark/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the Lingluo photo picker entry page', (tester) async {
    await tester.pumpWidget(const FilmWatermarkApp());

    expect(find.text('零落'), findsOneWidget);
    expect(find.text('用时间缝合所有的零落'), findsOneWidget);
    expect(find.text('选择照片'), findsOneWidget);
    expect(find.text('保存'), findsNothing);
  });
}
