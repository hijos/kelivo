import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BoundedIntegerField extends StatefulWidget {
  const BoundedIntegerField({
    super.key,
    required this.value,
    required this.minValue,
    required this.maxValue,
    required this.onChanged,
    this.width = 52,
    this.height = 32,
  });

  final int value;
  final int minValue;
  final int maxValue;
  final ValueChanged<int> onChanged;
  final double width;
  final double height;

  @override
  State<BoundedIntegerField> createState() => _BoundedIntegerFieldState();
}

class _BoundedIntegerFieldState extends State<BoundedIntegerField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.value}');
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant BoundedIntegerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) _commit();
  }

  void _commit() {
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed == null) {
      _controller.text = '${widget.value}';
      return;
    }
    final clamped = parsed.clamp(widget.minValue, widget.maxValue).toInt();
    _controller.text = '$clamped';
    if (clamped != widget.value) widget.onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        textAlign: TextAlign.center,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(3),
        ],
        onSubmitted: (_) => _commit(),
        style: TextStyle(
          fontSize: 14,
          color: cs.onSurface.withValues(alpha: 0.9),
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 7),
          filled: true,
          fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: cs.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: cs.primary),
          ),
        ),
      ),
    );
  }
}
