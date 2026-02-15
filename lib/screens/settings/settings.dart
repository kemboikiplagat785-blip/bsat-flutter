import 'package:bsat/components/dialogs/clear_history_dialog.dart';
import 'package:bsat/components/dialogs/confirm_delete_dialog.dart';
import 'package:bsat/components/dialogs/loading_dialog.dart';
import 'package:bsat/components/dialogs/success_dialog.dart';
import 'package:bsat/components/header.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/theme.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/theme_provider.dart';
import '../../utils/constants.dart';
import '../../utils/get_sim_cards.dart';

import 'package:package_info_plus/package_info_plus.dart';

class SettingsPage extends StatefulWidget {
  final bool isDashboard;
  const SettingsPage({super.key, this.isDashboard = false});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  var simCards = getSimCardsData();
  List<Widget> cards = [];

  bool autoRetrySectionOpened = false;
  bool themeSectionOpened = false;
  bool contactsSectionOpened = false;
  bool deleteHistorySectionOpened = false;
  bool anotherSectionIsOpened = false;

  bool smsRunning = false;
  bool dataRunning = false;

  bool autoRetrySms = false;
  bool autoRetryData = true;

  bool autoSaveContacts = false;

  var sharedPreferencesService = SharedPreferencesService();

  TextEditingController _postfixTextController = TextEditingController();
  TextEditingController _retryTimeoutController = TextEditingController();
  TextEditingController _deleteDurationController = TextEditingController();

  @override
  void initState() {
    super.initState();

    // getAndProcessCards();
    getStatuses();
  }

  void toogleSmsPaused() async {
    // isRunning = !isRunning;
    smsRunning = !smsRunning;
    await sharedPreferencesService.setSmsRunning(smsRunning).then((value) {
      // debugPrint("Status: ${!value}");
      getStatuses();
    });
  }

  void toogleDataPaused() async {
    // isRunning = !isRunning;
    dataRunning = !dataRunning;
    await sharedPreferencesService.setDataRunning(dataRunning).then((value) {
      // debugPrint("Status: ${!value}");
      getStatuses();
    });
  }

  void toogleSmsAutoRetry() async {
    // isRunning = !isRunning;
    autoRetrySms = !autoRetrySms;
    await sharedPreferencesService
        .setCanAutoRetrySms(autoRetrySms)
        .then((value) => getStatuses());
  }

  void toogleDataAutoRetry() async {
    // isRunning = !isRunning;
    autoRetryData = !autoRetryData;
    await sharedPreferencesService
        .setCanAutoRetryData(autoRetryData)
        .then((value) => getStatuses());
  }

  void toogleAutoSaveContacts() async {
    // isRunning = !isRunning;
    autoSaveContacts = !autoSaveContacts;
    await sharedPreferencesService
        .setAutoSaveContacts(autoSaveContacts)
        .then((value) => getStatuses());

    setState(() {});
  }

  void getStatuses() async {
    // debugPrint("Version ${packageInfo.version}");

    autoSaveContacts =
        await sharedPreferencesService.getAutoSaveContacts() ?? false;

    _postfixTextController.text =
        await sharedPreferencesService.getPostfixContactName() ?? '';

    _retryTimeoutController.text =
        (await sharedPreferencesService.getRetryMinutes() ?? '').toString();

    _deleteDurationController.text = (await sharedPreferencesService
            .getAutoDeleteAfterNumberOfDays()
            .then((value) => value.toString())) ??
        '';

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    var themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header(context, 'Settings', isDashboard: widget.isDashboard),
            InkWell(
              onTap: () {
                setState(() {
                  autoRetrySectionOpened = !autoRetrySectionOpened;
                  if (autoRetrySectionOpened) {
                    themeSectionOpened = false;
                    contactsSectionOpened = false;
                    deleteHistorySectionOpened = false;
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.only(
                  left: kPagePadding,
                  top: kPagePadding,
                  right: kPagePadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('AutoRetry'),
                        Icon(autoRetrySectionOpened
                            ? CupertinoIcons.chevron_up
                            : CupertinoIcons.chevron_down),
                      ],
                    ),
                    SizedBox(height: kPagePadding / 2),
                    if (autoRetrySectionOpened)
                      Container(
                        padding: kPagePaddingInsets,
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(kBorderRadius),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Retry failed requests the following number of times'),
                            SizedBox(height: kPagePadding / 2),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _retryTimeoutController,
                                    decoration: InputDecoration(
                                      label: Text('retry'),
                                      border: const OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                SizedBox(width: kPagePadding / 2),
                                ElevatedButton(
                                  onPressed: () async {
                                    showLoadingDialog(context);
                                    await sharedPreferencesService
                                        .setRetryMinutes(
                                          int.parse(
                                              _retryTimeoutController.text),
                                        )
                                        .then((value) => getStatuses());
                                    Navigator.pop(context);
                                    showSuccessDialog(context,
                                        text: 'Timeout set to ${_retryTimeoutController.text} minutes');
                                  },
                                  child: Text('Save'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            InkWell(
              onTap: () {
                setState(() {
                  themeSectionOpened = !themeSectionOpened;
                  if (themeSectionOpened) {
                    autoRetrySectionOpened = false;
                    contactsSectionOpened = false;
                    deleteHistorySectionOpened = false;
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.only(
                  left: kPagePadding,
                  top: kPagePadding,
                  right: kPagePadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Theme'),
                        Icon(themeSectionOpened
                            ? CupertinoIcons.chevron_up
                            : CupertinoIcons.chevron_down),
                      ],
                    ),
                    SizedBox(height: kPagePadding / 2),
                    if (themeSectionOpened)
                      Container(
                        padding: kPagePaddingInsets,
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(kBorderRadius),
                        ),
                        child: Wrap(
                          spacing: kPagePadding / 2,
                          runSpacing: kPagePadding / 2,
                          alignment: WrapAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: () {
                                themeProvider.setlightTheme();
                              },
                              child: Container(
                                padding: kPagePaddingInsets,
                                width: kPagePadding * 2,
                                decoration: BoxDecoration(
                                  borderRadius:
                                      BorderRadius.circular(kBorderRadius),
                                  color: kBgColor,
                                  border:
                                      themeProvider.currentTheme == lightTheme
                                          ? Border.all(
                                              color: kPrimaryColor,
                                              width: 2.0,
                                            )
                                          : null,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                themeProvider.setDarkTheme();
                              },
                              child: Container(
                                padding: kPagePaddingInsets,
                                width: kPagePadding * 2,
                                decoration: BoxDecoration(
                                  borderRadius:
                                      BorderRadius.circular(kBorderRadius),
                                  color: kSecondaryColor,
                                  border:
                                      themeProvider.currentTheme == darkTheme
                                          ? Border.all(
                                              color: kPrimaryColor,
                                              width: 2.0,
                                            )
                                          : null,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                themeProvider.setBrownTheme();
                              },
                              child: Container(
                      
                                padding: kPagePaddingInsets,
                                width: kPagePadding * 2,
                                decoration: BoxDecoration(
                                  borderRadius:
                                      BorderRadius.circular(kBorderRadius),
                                  color: kBrownBackground,
                                  border:
                                      themeProvider.currentTheme == brownTheme
                                          ? Border.all(
                                              color: kPrimaryColor,
                                              width: 2.0,
                                            )
                                          : null,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                themeProvider.setPinkTheme();
                              },
                              child: Container(
                                padding: kPagePaddingInsets,
                                width: kPagePadding * 2,
                                decoration: BoxDecoration(
                                  borderRadius:
                                      BorderRadius.circular(kBorderRadius),
                                  color: Color(0xFFFF69B4),
                                  border:
                                      themeProvider.currentTheme == pinkTheme
                                          ? Border.all(
                                              color: kPrimaryColor,
                                              width: 2.0,
                                            )
                                          : null,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                themeProvider.setIndigoColor();
                              },
                              child: Container(
                                padding: kPagePaddingInsets,
                                width: kPagePadding * 2,
                                decoration: BoxDecoration(
                                  borderRadius:
                                      BorderRadius.circular(kBorderRadius),
                                  color: kIndigoColor,
                                  border:
                                      themeProvider.currentTheme == indigoTheme
                                          ? Border.all(
                                              color: kPrimaryColor,
                                              width: 2.0,
                                            )
                                          : null,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                themeProvider.setDarkPurpleTheme();
                              },
                              child: Container(
                                padding: kPagePaddingInsets,
                                width: kPagePadding * 2,
                                decoration: BoxDecoration(
                                  borderRadius:
                                      BorderRadius.circular(kBorderRadius),
                                  color: Color(0xFF190b28),
                                  border: themeProvider.currentTheme ==
                                          darkPurpleTheme
                                      ? Border.all(
                                          color: kPrimaryColor,
                                          width: 2.0,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                themeProvider.setBlackAndWhiteTheme();
                              },
                              child: Container(
                                padding: kPagePaddingInsets,
                                width: kPagePadding * 2,
                                decoration: BoxDecoration(
                                  borderRadius:
                                      BorderRadius.circular(kBorderRadius),
                                  color: Colors.black,
                                  border: themeProvider.currentTheme ==
                                          blackAndWhiteTheme
                                      ? Border.all(
                                          color: kPrimaryColor,
                                          width: 2.0,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            InkWell(
              onTap: () {
                setState(() {
                  contactsSectionOpened = !contactsSectionOpened;
                  if (contactsSectionOpened) {
                    themeSectionOpened = false;
                    autoRetrySectionOpened = false;
                    deleteHistorySectionOpened = false;
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.only(
                  left: kPagePadding,
                  top: kPagePadding,
                  right: kPagePadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Contacts"),
                        Icon(contactsSectionOpened
                            ? CupertinoIcons.chevron_up
                            : CupertinoIcons.chevron_down)
                      ],
                    ),
                    const SizedBox(height: kPagePadding / 2),
                    if (contactsSectionOpened)
                      Container(
                        padding: kPagePaddingInsets,
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(kBorderRadius),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CheckboxListTile(
                              title: Text('Auto save contacts'),
                              value: autoSaveContacts,
                              onChanged: (value) => toogleAutoSaveContacts(),
                            ),
                            SizedBox(height: kPagePadding / 2),
                            Divider(
                              thickness: 1,
                              color: (Colors.grey[50])!.withOpacity(0.2),
                              // height: kPagePadding * 2,
                            ),
                            const SizedBox(height: kPagePadding / 2),
                            Text("Add the following to saved contact name"),
                            const SizedBox(height: kPagePadding / 2),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _postfixTextController,
                                    decoration: InputDecoration(
                                      hintText: 'e.g. Bingwa Customer',
                                      border: const OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: kPagePadding / 2),
                                ElevatedButton(
                                  onPressed: () async {
                                    showLoadingDialog(context);
                                    await sharedPreferencesService
                                        .setPostfixCOntactName(
                                          _postfixTextController.text,
                                        )
                                        .then((value) => getStatuses());
                                    Navigator.pop(context);
                                    showSuccessDialog(
                                        context, text: 'Name set successfuly');
                                  },
                                  child: Text('Save'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            InkWell(
              onTap: () {
                setState(() {
                  deleteHistorySectionOpened = !deleteHistorySectionOpened;
                  if (deleteHistorySectionOpened) {
                    themeSectionOpened = false;
                    autoRetrySectionOpened = false;
                    contactsSectionOpened = false;
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.only(
                  left: kPagePadding,
                  top: kPagePadding,
                  right: kPagePadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Delete History"),
                        Icon(
                          deleteHistorySectionOpened
                              ? CupertinoIcons.chevron_up
                              : CupertinoIcons.chevron_down,
                        ),
                      ],
                    ),
                    SizedBox(height: kPagePadding / 2),
                    if (deleteHistorySectionOpened)
                      Container(
                        padding: kPagePaddingInsets,
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(kBorderRadius),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Manually delete all transactions history"),
                            SizedBox(height: kPagePadding / 2),
                            Row(
                              children: [
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kErrorColor,
                                  ),
                                  onPressed: () async {
                                    // await showClearHistoryDialog(context);
                                    await showConfirmDeleteDialog(
                                      context,
                                      title: 'Warning',
                                      message:
                                          'Are you sure you want to clear all transaction history? This action cannot be undone.',
                                      btnText: 'Delete All',
                                    ).then((value) async {
                                      if (value == true) {
                                        await SQLiteService().deleteWhere(
                                          'transactions',
                                          '1=1',
                                          [],
                                        );
                                      }
                                    });
                                    showSuccessDialog(context,
                                        text: 'History cleared successfully');
                                  },
                                  child: Text('All'),
                                ),
                                SizedBox(width: kPagePadding),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kErrorColor,
                                  ),
                                  onPressed: () async {
                                    // await showClearHistoryDialog(context);
                                    await showDialog<void>(
                                      context: context,
                                      builder: (BuildContext context) {
                                        return ClearHistoryDialog();
                                      },
                                    );
                                  },
                                  child: Text('In time range'),
                                ),
                              ],
                            ),
                            SizedBox(height: kPagePadding / 2),
                            Divider(
                              thickness: 1,
                              color: (Colors.grey[50])!.withOpacity(0.2),
                              // height: kPagePadding * 2,
                            ),
                            SizedBox(height: kPagePadding),
                            Text('Auto delete Transactions older than'),
                            SizedBox(height: kPagePadding / 2),
                            Text('(use 0 to disable)', style: TextStyle(
                              fontSize: 12,
                              color: (Colors.grey[50])!.withOpacity(0.5),
                            ),),
                            SizedBox(height: kPagePadding / 3),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _deleteDurationController,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      label: Text('days'),
                                      border: const OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                SizedBox(width: kPagePadding / 2),
                                ElevatedButton(
                                  onPressed: () async {
                                    await SharedPreferencesService()
                                        .setAutoDeleteAfterNumberOfDays(
                                            int.parse(
                                                _deleteDurationController.text))
                                        .then((value) => getStatuses());
                                    showSuccessDialog(
                                      context,
                                      text: 'Duration set to ${_deleteDurationController.text} days',
                                    );
                                  },
                                  child: Text('Save'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: kPagePadding * 7),
          ],
        ),
      ),
    );
  }
}
