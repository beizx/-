import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:translation_app/services/reader/reader_paginator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const style = TextStyle(fontSize: 16, height: 1.8);

  test('splits text into non-empty paragraphs', () {
    expect(ReaderPaginator.splitParagraphs('第一段\n\n第二段\n   \n第三段'), [
      '第一段',
      '第二段',
      '第三段',
    ]);
    expect(ReaderPaginator.splitParagraphs(''), isEmpty);
  });

  test('applies the first-line indent only to paragraph starts', () {
    final paragraphs = ReaderPaginator.displayParagraphs(
      '第一段\n第二段',
      firstLineIndent: 2,
    );
    expect(paragraphs.first.startsWith('　　'), isTrue);
    expect(paragraphs.first.endsWith('第一段'), isTrue);
  });

  test('paginates a long chapter into multiple non-empty pages', () {
    final text = List.generate(
      60,
      (index) => '第${index + 1}段。${'海风与灯塔。' * 12}',
    ).join('\n');

    final pagination = ReaderPaginator.paginate(
      text: text,
      textStyle: style,
      maxWidth: 320,
      pageHeight: 300,
      paragraphSpacing: 8,
      firstLineIndent: 2,
    );

    expect(pagination.pages.length, greaterThan(1));
    expect(pagination.displayParagraphs, hasLength(60));
    for (final page in pagination.pages) {
      expect(page.fragments, isNotEmpty);
      for (final fragment in page.fragments) {
        expect(fragment.end, greaterThan(fragment.start));
        expect(
          fragment.end,
          lessThanOrEqualTo(
            pagination.displayParagraphs[fragment.paragraphIndex].length,
          ),
        );
      }
    }
    final covered = pagination.pages
        .expand((page) => page.fragments)
        .map((fragment) => fragment.textOf(pagination.displayParagraphs))
        .where((text) => text.trim().isNotEmpty)
        .length;
    expect(covered, greaterThan(60));
  });

  test('a shorter first page reserves room for the chapter title', () {
    final text = '海' * 900;
    final full = ReaderPaginator.paginate(
      text: text,
      textStyle: style,
      maxWidth: 320,
      pageHeight: 280,
      paragraphSpacing: 0,
    );
    final withHeader = ReaderPaginator.paginate(
      text: text,
      textStyle: style,
      maxWidth: 320,
      pageHeight: 280,
      firstPageHeight: 140,
      paragraphSpacing: 0,
    );

    int chars(ReaderPagination pagination, int page) => pagination
        .pages[page]
        .fragments
        .map((fragment) => fragment.textOf(pagination.displayParagraphs))
        .join()
        .length;

    expect(chars(withHeader, 0), lessThan(chars(full, 0)));
    expect(withHeader.pages.length, greaterThan(full.pages.length));
  });

  test('tiny page heights terminate instead of looping forever', () {
    final pagination = ReaderPaginator.paginate(
      text: '一二三四五六七八九十' * 30,
      textStyle: style,
      maxWidth: 120,
      pageHeight: 24,
      maxPages: 500,
    );
    expect(pagination.pages, isNotEmpty);
    expect(pagination.pages.length, lessThanOrEqualTo(500));
  });

  test('empty text produces no pages', () {
    final pagination = ReaderPaginator.paginate(
      text: '',
      textStyle: style,
      maxWidth: 320,
      pageHeight: 300,
    );
    expect(pagination.isEmpty, isTrue);
  });
}
