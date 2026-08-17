import 'package:flutter/material.dart';

class CalculatorWidget extends StatefulWidget {
  final Function(double) onApplyToPatientAmount;
  final Function(double) onApplyToStaffPayment;

  const CalculatorWidget({
    super.key,
    required this.onApplyToPatientAmount,
    required this.onApplyToStaffPayment,
  });

  @override
  State<CalculatorWidget> createState() => _CalculatorWidgetState();
}

class _CalculatorWidgetState extends State<CalculatorWidget> {
  String _expression = '';
  String _result = '0';

  void _onButtonPressed(String buttonText) {
    setState(() {
      if (buttonText == 'C') {
        _expression = '';
        _result = '0';
      } else if (buttonText == '⌫') {
        if (_expression.isNotEmpty) {
          _expression = _expression.substring(0, _expression.length - 1);
        }
      } else if (buttonText == '=') {
        _calculateResult();
      } else {
        _expression += buttonText;
      }
    });
  }

  void _calculateResult() {
    if (_expression.isEmpty) return;
    try {
      double res = _evaluateExpression(_expression);
      setState(() {
        _result = res.toStringAsFixed(2);
        if (_result.endsWith('.00')) {
          _result = _result.substring(0, _result.length - 3);
        }
      });
    } catch (e) {
      setState(() {
        _result = 'Error';
      });
    }
  }

  double _evaluateExpression(String exp) {
    String normalized = exp.replaceAll('×', '*');
    
    RegExp regExp = RegExp(r'(\d+\.?\d*|[\+\-\*/])');
    Iterable<Match> matches = regExp.allMatches(normalized);
    List<String> tokens = matches.map((m) => m.group(0)!).toList();
    
    if (tokens.isEmpty) return 0.0;
    
    if (tokens[0] == '-' && tokens.length > 1) {
      tokens[1] = '-${tokens[1]}';
      tokens.removeAt(0);
    }

    for (int i = 0; i < tokens.length; i++) {
      if (tokens[i] == '*' || tokens[i] == '/') {
        if (i > 0 && i < tokens.length - 1) {
          double left = double.parse(tokens[i - 1]);
          double right = double.parse(tokens[i + 1]);
          double res = tokens[i] == '*' ? left * right : left / right;
          tokens[i - 1] = res.toString();
          tokens.removeAt(i);
          tokens.removeAt(i);
          i--;
        }
      }
    }

    double total = double.parse(tokens[0]);
    for (int i = 1; i < tokens.length; i += 2) {
      String op = tokens[i];
      if (i + 1 < tokens.length) {
        double nextNum = double.parse(tokens[i + 1]);
        if (op == '+') total += nextNum;
        if (op == '-') total -= nextNum;
      }
    }
    
    return total;
  }

  Widget _buildButton(String text, {Color? backgroundColor, Color? textColor, int flex = 1, VoidCallback? onPressedOverride}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(2.0),
        child: InkWell(
          onTap: onPressedOverride ?? () => _onButtonPressed(text),
          borderRadius: BorderRadius.circular(8),
          child: Ink(
            height: 50,
            decoration: BoxDecoration(
              color: backgroundColor ?? Colors.white,
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: textColor ?? Colors.grey.shade800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final opBgColor = Colors.blue.shade50;
    final opTextColor = Colors.blue.shade700;
    final eqBgColor = Colors.blue.shade600;
    final eqTextColor = Colors.white;
    final clearTextColor = Colors.red;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _expression.isEmpty ? '0' : _expression,
                style: const TextStyle(fontSize: 18, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Text(
                _result,
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Row 1: C, /, ×, ⌫
        Row(
          children: [
            _buildButton('C', textColor: clearTextColor),
            _buildButton('/', backgroundColor: opBgColor, textColor: opTextColor),
            _buildButton('×', backgroundColor: opBgColor, textColor: opTextColor),
            _buildButton('⌫', backgroundColor: opBgColor, textColor: opTextColor),
          ],
        ),
        // Row 2: 7, 8, 9, -
        Row(
          children: [
            _buildButton('7'),
            _buildButton('8'),
            _buildButton('9'),
            _buildButton('-', backgroundColor: opBgColor, textColor: opTextColor),
          ],
        ),
        // Row 3: 4, 5, 6, +
        Row(
          children: [
            _buildButton('4'),
            _buildButton('5'),
            _buildButton('6'),
            _buildButton('+', backgroundColor: opBgColor, textColor: opTextColor),
          ],
        ),
        // Row 4 & 5 combined
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left 3 columns
            Expanded(
              flex: 3,
              child: Column(
                children: [
                  // Row 4: 1, 2, 3
                  Row(
                    children: [
                      _buildButton('1'),
                      _buildButton('2'),
                      _buildButton('3'),
                    ],
                  ),
                  // Row 5: 0 (span 2), .
                  Row(
                    children: [
                      _buildButton('0', flex: 2),
                      _buildButton('.'),
                    ],
                  ),
                ],
              ),
            ),
            // Right column: = (spanning 2 rows)
            Expanded(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.all(2.0),
                child: InkWell(
                  onTap: () => _onButtonPressed('='),
                  borderRadius: BorderRadius.circular(8),
                  child: Ink(
                    height: 104, // 50 * 2 + 4 (padding offsets)
                    decoration: BoxDecoration(
                      color: eqBgColor,
                      border: Border.all(color: eqBgColor),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '=',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: eqTextColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 360;

            final patientBtn = SizedBox(
              height: 46,
              child: FilledButton.icon(
                onPressed: () {
                  double? val = double.tryParse(_result);
                  if (val != null) widget.onApplyToPatientAmount(val);
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.person, size: 18),
                label: const Text(
                  'Apply to Patient',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            );

            final staffBtn = SizedBox(
              height: 46,
              child: OutlinedButton.icon(
                onPressed: () {
                  double? val = double.tryParse(_result);
                  if (val != null) widget.onApplyToStaffPayment(val);
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.payments_rounded, size: 18),
                label: const Text(
                  'Apply to Staff',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            );

            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  patientBtn,
                  const SizedBox(height: 10),
                  staffBtn,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: patientBtn),
                const SizedBox(width: 10),
                Expanded(child: staffBtn),
              ],
            );
          },
        ),
      ],
    );
  }
}

