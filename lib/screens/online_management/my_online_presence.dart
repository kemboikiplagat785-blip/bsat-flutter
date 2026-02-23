import 'dart:convert';
import 'package:bsat/components/dialogs/confirm_delete_dialog.dart';
import 'package:bsat/components/dialogs/loading_dialog.dart';
import 'package:bsat/components/dialogs/show_error_dialog.dart';
import 'package:bsat/components/dialogs/success_dialog.dart';
import 'package:bsat/services/auth_service.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../components/header.dart';
import '../../utils/constants.dart';
import 'edit_online_offer.dart';

class MyOnlinePresencePage extends StatefulWidget {
  const MyOnlinePresencePage({super.key});

  @override
  State<MyOnlinePresencePage> createState() => _MyOnlinePresencePageState();
}

class _MyOnlinePresencePageState extends State<MyOnlinePresencePage> {
  final TextEditingController _linkController = TextEditingController();
  final _prefs = SharedPreferencesService();
  String oldlinkExtension = '';
  List<Map<String, dynamic>> offerData = [];

  @override
  void initState() {
    super.initState();
    getData();
  }

  // ... [Logic: getData, _loadLinkExtension remain identical to your source] ...
  Future<void> getData() async {
    await _loadLinkExtension();
    final offersResult = await AuthService().getOffers(linkExtension: oldlinkExtension);
    if (offersResult['success']) {
      offerData = List<Map<String, dynamic>>.from(offersResult['data']['offers']);
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadLinkExtension() async {
    String? link = await _prefs.getLinkExtension();
    if (link != null) {
      _linkController.text = link;
      oldlinkExtension = link;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header(context, 'Online Presence'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: kPagePadding),
                  _buildSectionLabel('Public Identity'),
                  _buildLinkSection(theme),
                  
                  const SizedBox(height: 32),
                  _buildSectionLabel('Payment Configuration'),
                  _buildPaymentMethodCard(theme),

                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionLabel('Active Offers'),
                      _buildAddButton(context),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (offerData.isEmpty)
                    _buildEmptyState()
                  else
                    ...offerData.map((offer) => _buildModernOfferCard(context, offer)),
                  
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Modernist UI Components ---

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          // color: kGrayColor,
        ),
      ),
    );
  }

  Widget _buildLinkSection(ThemeData theme) {
    bool isChanged = _linkController.text != oldlinkExtension;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(kBorderRadius),
        border: Border.all(color: theme.dividerColor.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(CupertinoIcons.link, size: 18, color: kPrimaryColor),
                const SizedBox(width: 12),
                const Text('bingwa.bsat.co.ke/', style: TextStyle(fontSize: 14)),
                Expanded(
                  child: TextField(
                    controller: _linkController,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      hintText: 'username',
                    ),
                    onChanged: (v) => setState(() {}),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: theme.dividerColor.withOpacity(0.03),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: 'https://bingwa.bsat.co.ke/${_linkController.text}'));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied')));
                    },
                    icon: const Icon(CupertinoIcons.doc_on_doc, size: 16),
                    label: const Text('Copy'),
                    style: TextButton.styleFrom(foregroundColor: kGrayColor),
                  ),
                ),
                const VerticalDivider(),
                Expanded(
                  child: TextButton.icon(
                    onPressed: !isChanged ? null : () async => _handleUpdateLink(),
                    icon: const Icon(CupertinoIcons.cloud_upload, size: 16),
                    label: const Text('Update'),
                    style: TextButton.styleFrom(
                      foregroundColor: isChanged ? kPrimaryColor : kGrayColor.withOpacity(0.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(kBorderRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row(
          //   children: [
          //     Expanded(
          //       child: _buildChoiceChip('Lipa na Mpesa', true),
          //     ),
          //     const SizedBox(width: 8),
          //     Expanded(
          //       child: _buildChoiceChip('Send Money', true),
          //     ),
          //   ],
          // ),
          const Text('Mobile number to receive payments'),
          const SizedBox(height: 16),
          TextField(
            decoration: InputDecoration(
              filled: true,
              fillColor: theme.scaffoldBackgroundColor,
              hintText: 'M-Pesa Number',
              prefixIcon: const Icon(CupertinoIcons.phone_fill, size: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(kBorderRadius),
                borderSide: BorderSide.none,
              ),
              suffixIcon: TextButton(onPressed: () {}, child: const Text('Save')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChoiceChip(String label, bool selected) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: selected ? kPrimaryColor.withOpacity(0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(kBorderRadius),
        border: Border.all(color: selected ? kPrimaryColor : kGrayColor.withOpacity(0.2)),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: selected ? kPrimaryColor : kGrayColor,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildModernOfferCard(BuildContext context, Map<String, dynamic> offer) {
    final offerData = jsonDecode(offer['offer_data']);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(kBorderRadius),
        border: Border.all(color: kPrimaryColor.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kPrimaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(kBorderRadius),
            ),
            child: const Icon(CupertinoIcons.cart_fill, color: kPrimaryColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'KSH ${offerData['amount']}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
                Text(
                  '${offerData['bundleQuantity']} ${offerData['bundleQuantityUnit']} • ${offerData['duration']} ${offerData['durationUnit']}',
                  style: const TextStyle(color: kPrimaryColor, fontSize: 14),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _editOffer(offer),
            icon: const Icon(CupertinoIcons.pencil_circle, color: kPrimaryColor),
          ),
          IconButton(
            onPressed: () => _deleteOffer(offer['id']),
            icon: const Icon(CupertinoIcons.trash_circle, color: kErrorColor),
          ),
        ],
      ),
    );
  }

  Widget _buildAddButton(BuildContext context) {
    return GestureDetector(
      onTap: () => _editOffer(null),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: kPrimaryColor,
          borderRadius: BorderRadius.circular(kBorderRadius),
        ),
        child: const Row(
          children: [
            Icon(Icons.add, color: Colors.white, size: 16),
            SizedBox(width: 4),
            Text('ADD', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Text('No active offers found.', style: TextStyle(color: kGrayColor.withOpacity(0.5))),
      ),
    );
  }

  // --- Action Handlers ---

  Future<void> _handleUpdateLink() async {
    HapticFeedback.mediumImpact();
    showLoadingDialog(context, text: "Updating Link...");
    final result = await AuthService().updateLinkExtension(newLinkExtension: _linkController.text);
    Navigator.pop(context); // close loading
    if (result['success']) {
      await _prefs.setLinkExtension(_linkController.text);
      oldlinkExtension = _linkController.text;
      showSuccessDialog(context, text: "Identity updated.");
      setState(() {});
    } else {
      showErrorDialog(context, "Error", result['message']);
    }
  }

  void _editOffer(Map<String, dynamic>? offer) async {
    await Navigator.of(context).push(CupertinoPageRoute(
      builder: (_) => EditOnlineOffer(
        index: offer?['id'],
        existingData: offer != null ? jsonDecode(offer['offer_data']) : null,
      ),
    ));
    getData();
  }

  void _deleteOffer(int id) async {
    final confirmed = await showConfirmDeleteDialog(context) ?? false;
    if (confirmed) {
      showLoadingDialog(context, text: "Removing...");
      final response = await AuthService().deleteOnlineOffer(id);
      Navigator.pop(context);
      if (response['success']) {
        showSuccessDialog(context, text: "Offer removed.");
        getData();
      }
    }
  }
}