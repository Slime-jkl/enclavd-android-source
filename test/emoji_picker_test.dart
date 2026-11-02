import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/widgets/emoji_picker_sheet.dart';

void main() {
  test('pads a side glued to a word', () {
    final c = TextEditingController(text: 'hi smile')
      ..selection = const TextSelection.collapsed(offset: 8);
    insertEmojiShortcode(c, 'smile');
    expect(c.text, 'hi smile :smile:');
  });

  test('leaves existing whitespace alone', () {
    final c = TextEditingController(text: 'hi  there')
      ..selection = const TextSelection.collapsed(offset: 3);
    insertEmojiShortcode(c, 'fire');
    expect(c.text, 'hi :fire: there');
  });

  test('replaces a selection', () {
    final c = TextEditingController(text: 'say it')
      ..selection = const TextSelection(baseOffset: 4, extentOffset: 6);
    insertEmojiShortcode(c, 'fire');
    expect(c.text, 'say :fire:');
  });

  test('respects the max length', () {
    final c = TextEditingController(text: 'abc')
      ..selection = const TextSelection.collapsed(offset: 3);
    insertEmojiShortcode(c, 'smile', maxLength: 5);
    expect(c.text, 'abc');
  });
}
