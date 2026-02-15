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

  // {success: true, data: {offers: [{id: 1, user_id: 2, link_extension: markizoe, offer_data: {"bundleQuantity":23,"bundleQuantityUnit":"MB","duration":24,"durationUnit":"hours","amount":25}, created_at_millis: 1761469708260}, {id: 2, user_id: 2, link_extension: markizoe, offer_data: {"bundleQuantity":23,"bundleQuantityUnit":"MB","duration":22,"durationUnit":"hours","amount":21}, created_at_millis: 1761470252567}]}}
  String linkExtension = '';
  List<Map<String, dynamic>> offerData = [];

  List<String> paymentMethods = [
    'Till Number',
    'Mobile Number',
  ];

  @override
  void initState() {
    super.initState();

    getData();
  }

  Future<void> getData() async {
    await _loadLinkExtension();

    // get offers
    final offersResult =
        await AuthService().getOffers(linkExtension: oldlinkExtension);
    //print(offersResult);
    if (offersResult['success']) {
      // Handle successful offers retrieval

      offerData =
          List<Map<String, dynamic>>.from(offersResult['data']['offers']);
      // offerData = jsonDecode(offersResult['data']['offers']) as Map<String, dynamic>;
    } else {
      // Handle errors
    }
    setState(() {});
  }

  Future<void> _loadLinkExtension() async {
    String? linkExtension = await _prefs.getLinkExtension();

    if (linkExtension != null) {
      _linkController.text = linkExtension;
      oldlinkExtension = linkExtension;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header(context, 'Online Presence'),
            Container(
              padding: kPagePaddingInsets,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'My Link',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: kPagePadding / 2),
                  Container(
                    padding: const EdgeInsets.only(
                      left: kPagePadding,
                      // right: 2,
                      // top: kPagePadding,
                      // bottom: kPagePadding,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(kBorderRadius),
                        bottomLeft: Radius.circular(kBorderRadius),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'https://bingwa.bsat.co.ke/',
                          style: TextStyle(color: Colors.grey),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _linkController,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              hintText: 'your-link',
                            ),
                            onChanged: (value) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: kPagePadding / 2),
                  // row with copy and update buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(kBorderRadius),
                          ),
                          backgroundColor: Theme.of(context).cardColor,
                          foregroundColor:
                              Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                        onPressed: () {
                          // copy to clipboard
                          Clipboard.setData(
                            ClipboardData(
                              text:
                                  'https://bingwa.bsat.co.ke/${_linkController.text}',
                            ),
                          );

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Link copied to clipboard'),
                            ),
                          );
                        },
                        child: Text('Copy Link'),
                      ),
                      const SizedBox(width: kPagePadding),
                      ElevatedButton(
                        // not enabled if link is unchanged

                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(kBorderRadius),
                          ),
                          backgroundColor:
                              _linkController.text == oldlinkExtension
                                  ? Theme.of(context).cardColor
                                  : kPrimaryColor,
                          foregroundColor: kIndigoColor,
                        ),
                        onPressed: _linkController.text == oldlinkExtension
                            ? null
                            : () async {
                                showLoadingDialog(context,
                                    text: "Updating Link...");

                                String linkExtension = _linkController.text;
                                final result = await AuthService()
                                    .updateLinkExtension(
                                        newLinkExtension: linkExtension);
                                if (result['success']) {
                                  await _prefs.setLinkExtension(linkExtension);

                                  oldlinkExtension = linkExtension;

                                  if (context.mounted) {
                                    Navigator.of(context)
                                        .pop(); // close loading dialog
                                    showSuccessDialog(context,
                                        text:
                                            "Link updated successfully to https://bingwa.bsat.co.ke/$linkExtension");
                                  }
                                  setState(() {});
                                } else {
                                  if (context.mounted) {
                                    Navigator.of(context)
                                        .pop(); // close loading dialog
                                    showErrorDialog(
                                      context,
                                      "Failed to update link",
                                      result['message'],
                                    );
                                  }
                                }
                              },
                        child: Text('Update Link'),
                      ),
                    ],
                  ),
                  const SizedBox(height: kPagePadding),
                  Divider(),
                  const SizedBox(height: kPagePadding * 2),
                  Text(
                    'Payment method',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: kPagePadding / 2),
                  Text('Get paid via:'),
                  const SizedBox(height: kPagePadding / 3),
                  // row with 2 check boxes
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          color: Theme.of(context).cardColor,
                          child: CheckboxListTile(
                            side: BorderSide.none,
                            value: true,
                            onChanged: (value) {},
                            title: Text('Lipa na Mpesa'),
                          ),
                        ),
                      ),
                      Expanded(
                        child: CheckboxListTile(
                          side: BorderSide.none,
                          value: false,
                          onChanged: (value) {},
                          title: Text('Send money'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: kPagePadding / 2),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: 'Number',
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(kBorderRadius),
                              borderSide: BorderSide(
                                color: Theme.of(context).dividerColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: kPagePadding / 2),
                      TextButton(
                        onPressed: () {},
                        child: Text('Update'),
                      ),
                    ],
                  ),
                  const SizedBox(height: kPagePadding),
                  Divider(),
                  const SizedBox(height: kPagePadding * 2),
                  Text(
                    'Offers on sale',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: kPagePadding / 2),
                  offerData.isEmpty
                      ? Text('No offers available. Add a new offer.')
                      : Column(
                          children: offerData
                              .map(
                                (offer) => Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: kPagePadding / 2,
                                  ),
                                  child: _buildOfferCard(
                                    context: context,
                                    offer: offer,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                  const SizedBox(height: kPagePadding / 2),
                  Wrap(
                    spacing: kPagePadding / 2,
                    runSpacing: kPagePadding / 2,
                    children: [
                      InkWell(
                        onTap: () async {
                          await Navigator.of(context).push(
                            PageRouteBuilder(
                              pageBuilder:
                                  (context, animation, secondaryAnimation) =>
                                      EditOnlineOffer(),
                              transitionsBuilder: (
                                context,
                                animation,
                                secondaryAnimation,
                                child,
                              ) {
                                return CupertinoPageTransition(
                                  primaryRouteAnimation: animation,
                                  secondaryRouteAnimation: secondaryAnimation,
                                  linearTransition: true,
                                  child: child,
                                );
                              },
                            ),
                          );

                          await getData();
                        },
                        child: Container(
                          padding: kPagePaddingInsets,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(kBorderRadius),
                            color: Theme.of(context).cardColor,
                          ),
                          child: Icon(Icons.add),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfferCard({
    required BuildContext context,
    required Map<String, dynamic> offer,
  }) {
    final index = offer['id'];
    final offerData = jsonDecode(offer['offer_data']) as Map<String, dynamic>;
    //print("Building offer card for offerData: $offer");
    return Container(
      padding: kPagePaddingInsets,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kBorderRadius),
        color: Theme.of(context).cardColor,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'KSH ${offerData['amount']}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: kPagePadding / 2),
              Row(
                children: [
                  Text(
                      '${offerData['bundleQuantity'].toString()} ${offerData['bundleQuantityUnit']} '),
                  // const SizedBox(width: kPagePadding),
                  Text(
                      '$interpunct ${offerData['durationUnit'] == 0 ? '' : offerData['duration']} ${offerData['durationUnit']}'),
                ],
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                style: IconButton.styleFrom(
                  foregroundColor: kIndigoColor,
                  // backgroundColor: Theme.of(context).cardColor,
                  backgroundColor: kIndigoColor.withOpacity(0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(kBorderRadius),
                  ),
                ),
                onPressed: () async {
                  await Navigator.of(context).push(
                    PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) =>
                          EditOnlineOffer(
                        index: index,
                        existingData: offerData,
                      ),
                      transitionsBuilder: (
                        context,
                        animation,
                        secondaryAnimation,
                        child,
                      ) {
                        return CupertinoPageTransition(
                          primaryRouteAnimation: animation,
                          secondaryRouteAnimation: secondaryAnimation,
                          linearTransition: true,
                          child: child,
                        );
                      },
                    ),
                  );

                  await getData();
                },
                icon: Icon(
                  CupertinoIcons.pen,
                ),
              ),
              const SizedBox(width: kPagePadding),
              GestureDetector(
                onTap: () async {
                  // delete offer
                  final confirmed =
                      await showConfirmDeleteDialog(context) ?? false;
                  if (confirmed) {
                    // Proceed with deletion
                    showLoadingDialog(context, text: "Deleting Offer...");
                    final response =
                        await AuthService().deleteOnlineOffer(offer['id']);
                    Navigator.of(context).pop(); // close loading dialog
                    //print("Delete Response: $response");
                    if (response['success']) {
                      if (context.mounted) {
                        showSuccessDialog(context,
                            text: "Offer deleted successfully.");
                        await getData();
                      }
                    }
                  } else {
                    // Deletion cancelled
                  }
                },
                child: Icon(
                  CupertinoIcons.trash,
                  color: Colors.red,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
