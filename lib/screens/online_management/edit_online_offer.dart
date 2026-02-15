import 'package:bsat/components/dialogs/success_dialog.dart';
import 'package:bsat/components/header.dart';
import 'package:bsat/services/auth_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/material.dart';

import '../../components/dialogs/loading_dialog.dart';
import '../../services/shared_preferences_service.dart';

class EditOnlineOffer extends StatefulWidget {
  final Map<String, dynamic>? existingData;
  final int? index;

  const EditOnlineOffer({super.key, this.existingData, this.index});

  @override
  State<EditOnlineOffer> createState() => _EditOnlineOfferState();
}

class _EditOnlineOfferState extends State<EditOnlineOffer> {
  //   bundleQuantity: 10,
  // bundleQuantityUnit: 'GB',
  // duration: 30,
  // durationUnit: 'days',
  // amount: 5.99
  String linkExtension = '';
  final TextEditingController _bundleQuantityController =
      TextEditingController();
  final TextEditingController _durationController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  String selectedBundleUnit = 'MB';
  String selectedDurationUnit = 'hours';

  List bundleUnits = ['MB', 'GB', 'sms', 'minutes', 'dabo dabo'];
  List durationUnits = ['minutes', 'till midnight', 'hours', 'days', 'weeks', 'months'];

  void fillData() async {
    linkExtension = await SharedPreferencesService().getLinkExtension() ?? '';
    // Load existing data here and set to controllers and selected units
    // For example:

    if (widget.existingData != null) {
      // //print('Existing Data: ${widget.existingData}');
      // CREATE TABLE IF NOT EXISTS online_offers (
      //   id INT AUTO_INCREMENT PRIMARY KEY,
      //   user_id INT NOT NULL,
      //   link_extension VARCHAR(255) NOT NULL,
      //   offer_data JSON NOT NULL,
      //   created_at_millis BIGINT NOT NULL DEFAULT (UNIX_TIMESTAMP() * 1000),
      //   FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
      //   FOREIGN KEY (link_extension) REFERENCES users(link_extension) ON DELETE CASCADE,
      //   INDEX idx_user_id (user_id),
      //   INDEX idx_link_extension (link_extension)
      // );

      // offerData = {
      //   bundleQuantity: 10,
      //   bundleQuantityUnit: 'GB',
      //   duration: 30,
      //   durationUnit: 'days',
      //   amount: 5.99
      // };
      _bundleQuantityController.text =
          widget.existingData?['bundleQuantity'].toString() ?? '';
      selectedBundleUnit = widget.existingData?['bundleQuantityUnit'] ?? 'MB';
      _durationController.text =
          widget.existingData?['duration'].toString() ?? '';
      selectedDurationUnit = widget.existingData?['durationUnit'] ?? 'hours';
      _amountController.text = widget.existingData?['amount'].toString() ?? '';
    }

    setState(() {});
  }

  Future<void> postData() async {
    // Post updated data to server or save locally
    AuthService authService = AuthService();
    showLoadingDialog(context);
    Map<String, dynamic> updatedData = {
      'bundleQuantity': double.tryParse(_bundleQuantityController.text) ?? 0,
      'bundleQuantityUnit': selectedBundleUnit,
      'duration': selectedDurationUnit == 'till midnight'
          ? 0
          : int.tryParse(_durationController.text) ?? 0,
      'durationUnit': selectedDurationUnit,
      'amount': double.tryParse(_amountController.text) ?? 0.0,
    };

    var response = {};

    if (widget.existingData == null) {
      response = await authService.createOnlineOffer(
        linkExtension,
        updatedData,
      );
    } else {
      //print('Posting data for existing offer');
      response = await authService.updateOnlineOffer(
        widget.index!,
        updatedData,
      );
    }
    // Call your API or service to save the updated data
    Navigator.pop(context);

    if (response['success']) {
      // Successfully updated
      await showSuccessDialog(context, text: "Offer saved successfully");
      Navigator.of(context).pop(); // Go back after saving
    } else {
      // Handle error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update offer : ${response['message']}')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    fillData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            header(context, "Edit online listing"),
            const SizedBox(height: kPagePadding),
            Padding(
              padding: kPagePaddingInsets,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("The client receives"),
                  const SizedBox(height: kPagePadding / 2),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: _buildTextField(
                          'Bundle Quantity',
                          _bundleQuantityController,
                          (value) {},
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      // dropdown for bundle unit
                      const SizedBox(width: kPagePadding / 3),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          value: selectedBundleUnit,
                          onChanged: (value) {
                            setState(() {
                              selectedBundleUnit = value!;
                            });
                          },
                          decoration: InputDecoration(
                            // labelText: 'Bundle Unit',
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(kBorderRadius),
                            ),
                          ),
                          items: bundleUnits
                              .map((unit) => DropdownMenuItem<String>(
                                    value: unit,
                                    child: Text(unit),
                                  ))
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: kPagePadding),
                  Text("Valid for"),
                  const SizedBox(height: kPagePadding / 2),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: _buildTextField(
                          'Duration',
                          _durationController,
                          (value) {},
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      // dropdown for duration unit
                      const SizedBox(width: kPagePadding / 3),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          value: selectedDurationUnit,
                          onChanged: (value) {
                            setState(() {
                              selectedDurationUnit = value!;
                            });
                          },
                          decoration: InputDecoration(
                            // labelText: 'Duration Unit',
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(kBorderRadius),
                            ),
                          ),
                          items: durationUnits
                              .map((unit) => DropdownMenuItem<String>(
                                    value: unit,
                                    child: Text(unit),
                                  ))
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: kPagePadding),
                  Text("Offer will cost"),
                  const SizedBox(height: kPagePadding / 2),
                  _buildTextField(
                    'Price (Ksh)',
                    _amountController,
                    (value) {},
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: kPagePadding * 2),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      minimumSize: Size(double.infinity, 50),
                      foregroundColor: kPrimaryColor,
                      backgroundColor: Colors.transparent,
                      // foregroundColor: kIndigoColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(kBorderRadius),
                      ),
                    ),
                    onPressed: () async {
                      await postData();
                    },
                    child: const Text('Save Changes'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    Function(String) onChanged, {
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kBorderRadius),
        ),
      ),
      onChanged: onChanged,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter $label';
        }
        return null;
      },
    );
  }
}
