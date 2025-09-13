import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

class ChipInputField extends StatelessWidget {
  final List<int> chips;
  final TextEditingController controller;
  final VoidCallback onAddChip;
  final Function(String) onRemoveChip;
  final TextInputType keyboardType;
  final double spacing;
  final double borderRadius;
  final Color addIconColor;

  const ChipInputField({
    super.key,
    required this.chips,
    required this.controller,
    required this.onAddChip,
    required this.onRemoveChip,
    this.keyboardType = TextInputType.text,
    this.spacing = 8.0,
    this.borderRadius = 8.0,
    this.addIconColor = Colors.blue,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: spacing,
          children: chips.map((chip) {
            return Chip(
              label: Text(chip.toString()),
              deleteIcon: const Icon(Icons.close),
              onDeleted: () => onRemoveChip(chip.toString()),
            );
          }).toList(),
        ),
        SizedBox(height: spacing),
        Row(
          children: [
            Expanded(
              child: TextField(
                keyboardType: keyboardType,
                controller: controller,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(borderRadius),
                  ),
                ),
                onSubmitted: (_) => onAddChip(),
              ),
            ),
            IconButton(
              onPressed: onAddChip,
              icon: Icon(
                CupertinoIcons.add_circled,
                color: addIconColor,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
