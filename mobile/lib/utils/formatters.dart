import 'package:flutter/services.dart';

class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  static const separator = '.';

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    String newValueText = newValue.text.replaceAll(separator, '');
    
    // Only allow digits
    if (newValueText.isNotEmpty && int.tryParse(newValueText) == null) {
      return oldValue;
    }

    String newString = '';
    if (newValueText.isNotEmpty) {
      for (int i = newValueText.length - 1; i >= 0; i--) {
        newString = newValueText[i] + newString;
        if ((newValueText.length - i) % 3 == 0 && i != 0) {
          newString = separator + newString;
        }
      }
    }

    // Cursor position fix
    int offset = newValue.selection.end + (newString.length - newValue.text.length);
    if (offset < 0) offset = 0;
    if (offset > newString.length) offset = newString.length;

    return TextEditingValue(
      text: newString,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

class AppFormatters {
  static String formatPrice(dynamic price) {
    if (price == null) return '';
    
    String priceStr;
    if (price is double || price is int) {
      priceStr = price is double ? price.toStringAsFixed(0) : price.toString();
    } else {
      priceStr = price.toString().split('.').first; // deal with '2500.0' strings
    }

    String newString = '';
    for (int i = priceStr.length - 1; i >= 0; i--) {
      newString = priceStr[i] + newString;
      if ((priceStr.length - i) % 3 == 0 && i != 0) {
        newString = '.' + newString;
      }
    }
    return newString;
  }
}
