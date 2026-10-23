import 'package:flutter/material.dart';

class PaymentSection extends StatelessWidget {
  final String paymentStatus;
  final ValueChanged<String?> onPaymentStatusChanged;
  final List<String> paymentOptions;

  const PaymentSection({
    super.key,
    required this.paymentStatus,
    required this.onPaymentStatusChanged,
    required this.paymentOptions,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      decoration: const InputDecoration(
        labelText: 'حالة الدفع',
        border: OutlineInputBorder(),
      ),
      value: paymentStatus,
      items: paymentOptions
          .map((option) => DropdownMenuItem(
                value: option,
                child: Text(option),
              ))
          .toList(),
      onChanged: onPaymentStatusChanged,
      validator: (val) =>
          val == null || val.isEmpty ? 'يرجى اختيار حالة الدفع' : null,
    );
  }
}
