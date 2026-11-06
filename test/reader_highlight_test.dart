import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:translation_app/widgets/reader_content.dart';

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

Text _text(WidgetTester tester, String content) {
  return tester.widget<Text>(find.textContaining(content).first);
}

void main() {
  testWidgets('only the paragraph owning the spoken sentence turns rich', (
    tester,
  ) async {
    final highlight = ValueNotifier<String?>('第二句。');
    addTearDown(highlight.dispose);

    await tester.pumpWidget(
      _host(
        Column(
          children: [
            for (final paragraph in const ['第一句。', '第二句。'])
              ReaderHighlightedParagraph(
                text: paragraph,
                style: const TextStyle(fontSize: 16),
                align: TextAlign.start,
                highlight: highlight,
                highlightColor: Colors.yellow,
              ),
          ],
        ),
      ),
    );

    expect(_text(tester, '第一句。').textSpan, isNull);
    expect(_text(tester, '第二句。').textSpan, isNotNull);

    highlight.value = '第一句。';
    await tester.pump();

    expect(_text(tester, '第一句。').textSpan, isNotNull);
    expect(_text(tester, '第二句。').textSpan, isNull);

    highlight.value = null;
    await tester.pump();

    expect(_text(tester, '第一句。').textSpan, isNull);
    expect(_text(tester, '第二句。').textSpan, isNull);
  });

  testWidgets('a paragraph that does not contain the sentence stays plain', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ReaderHighlightedParagraph(
          text: '海面起了雾。',
          style: const TextStyle(fontSize: 16),
          align: TextAlign.start,
          highlight: ValueNotifier<String?>('完全不存在的句子'),
        ),
      ),
    );

    expect(_text(tester, '海面起了雾').textSpan, isNull);
  });

  testWidgets('without a listenable the paragraph renders as plain text', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const ReaderHighlightedParagraph(
          text: '灯塔仍亮着。',
          style: TextStyle(fontSize: 16),
          align: TextAlign.start,
          highlight: null,
        ),
      ),
    );

    expect(_text(tester, '灯塔仍亮着').textSpan, isNull);
  });

  test('speech highlight notifies only the paragraphs that changed', () {
    final bus = ReaderSpeechHighlight();
    final calls = <int>[];
    bus.addParagraphListener(0, () => calls.add(0));
    bus.addParagraphListener(1, () => calls.add(1));
    bus.addParagraphListener(2, () => calls.add(2));

    bus.update(text: '第二句。', paragraphIndex: 1);
    expect(calls, [1]);

    calls.clear();
    bus.update(text: '第三句。', paragraphIndex: 2);
    expect(calls, containsAll(<int>[1, 2]));
    expect(calls, isNot(contains(0)));

    calls.clear();
    bus.update(text: null, paragraphIndex: null);
    expect(calls, [2]);
    bus.dispose();
  });
}
