import 'package:flutter_test/flutter_test.dart';
import 'package:mobiledaw/arrange/mixer_sheet.dart';

void main() {
  test('gain label in dB', () {
    expect(gainLabel(1), '+0.0 dB');
    expect(gainLabel(0.5), '-6.0 dB');
    expect(gainLabel(2), '+6.0 dB');
    expect(gainLabel(0), '-∞ dB');
  });
  test('pan label', () {
    expect(panLabel(0), 'C');
    expect(panLabel(-0.25), 'L25');
    expect(panLabel(1), 'R100');
  });
}
