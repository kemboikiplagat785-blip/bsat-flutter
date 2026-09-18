import 'package:bsat/components/dialogs/confirm_delete_dialog.dart';
import 'package:bsat/services/backend_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../components/device_card.dart';
import '../../components/header.dart';
import '../../services/auth_service.dart';
import '../../services/shared_preferences_service.dart';
import '../../services/sqlite_service.dart';
import '../../utils/constants.dart';
import 'login.dart';
import 'register_device.dart';

class SearchDevicePage extends StatefulWidget {
  final String query;
  const SearchDevicePage({super.key, this.query = ""});

  @override
  State<SearchDevicePage> createState() => _SearchDevicePageState();
}

class _SearchDevicePageState extends State<SearchDevicePage> {
  TextEditingController searchController = TextEditingController();

  List<Map<String, dynamic>> devices = [];
  List<Map<String, dynamic>> pairedDevices = [];

  bool isLoading = false;

  void checkIfLoggedIn() async {
    // isSignedIn = await myFirebaseAuth.isSignedIn();
    bool isSignedIn = await AuthService().isLoggedIn();
    String myDeviceName =
        await SharedPreferencesService().getDeviceName() ?? "Unknown Device";

    if (!isSignedIn && mounted) {
      // Navigate to login if not signed in
      Navigator.of(context).pushReplacement(
        CupertinoPageRoute(
          builder: (context) => LoginPage(),
        ),
      );
    } else if (myDeviceName == "Unknown Device") {
      // If signed in but no device registered, navigate to device registration
      Navigator.of(context).pushReplacement(
        CupertinoPageRoute(
          builder: (context) => RegisterDevicePage(),
        ),
      );
    }

    setState(() {});
  }

  void loadPairedDevices() async {
    pairedDevices = await BackendService()
        .get('/api/device/whitelisted')
        .then((response) async {
      if (response['success']) {
        await SQLiteService().deleteWhere('whitelistedDevices', '1=1', []);
        final data = response['data'];
        if (data != null && data['devices'] != null) {
          List<Map<String, dynamic>> devices =
              List<Map<String, dynamic>>.from(data['devices']);
          await SQLiteService().clearTable('whitelistedDevices');
          for (var device in devices) {
            await SQLiteService().insertStuff(device, 'whitelistedDevices');
          }
          return devices;
        }
        return <Map<String, dynamic>>[];
      } else {
        pairedDevices = await SQLiteService().queryAll('whitelistedDevices');
        return <Map<String, dynamic>>[];
      }
    });
    setState(() {});
  }

  void searchDevices() async {
    setState(() {
      isLoading = true;
    });
    //print("Searching for device: ${searchController.text}");
    Map response =
        await AuthService().searchDevice(query: searchController.text);

    //print(response);

    if (response['success']) {
      // Handle successful search
      //print("Search Results: ${response['data']}");

      setState(() {
        devices = List<Map<String, dynamic>>.from(response['data']["devices"]);
      });
    } else {
      // Handle search error
      //print("Search Error: ${response['message']}");
    }
    setState(() {
      isLoading = false;
    });
  }

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    searchController.text = widget.query;
    checkIfLoggedIn();
    loadPairedDevices();
    if (widget.query.isNotEmpty) {
      searchDevices();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            header(context, "Search Device"),
            const SizedBox(height: kPagePadding * 2),
            if (pairedDevices.isNotEmpty && searchController.text.isEmpty)
              ...pairedDevices.map((device) => Padding(
                    padding: EdgeInsets.only(
                        bottom: kPagePadding / 2,
                        left: kPagePadding,
                        right: kPagePadding),
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).pop(device);
                      },
                      child: deviceCard(
                        context: context,
                        deviceName: device['device_name'],
                        iconData: Icons.check_circle_outline_rounded,
                      ),
                    ),
                  )),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: kPagePadding / 2,
                children: [
                  TextField(
                    onSubmitted: (value) => searchDevices(),
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: 'Search (email, id, name)',
                      // prefixIcon: Icon(Icons.search),
                      suffixIcon: IconButton(
                        icon: Icon(Icons.search),
                        onPressed: () => searchDevices(),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(kBorderRadius),
                        // borderSide: BorderSide.none,
                        borderSide: BorderSide(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                      // filled: true,
                    ),
                  ),
                  const SizedBox(height: kPagePadding / 2),
                  Text(
                    "Found ${devices.length} device(s)",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  // const SizedBox(height: kPagePadding / 2),
                  if (isLoading)
                    Padding(
                      padding: const EdgeInsets.only(top: kPagePadding),
                      child: Center(
                        child: CupertinoActivityIndicator(
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                    )
                  else if (devices.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: kPagePadding),
                      child: Text(
                        "\n\nTry searching with different keywords.\n\n\nMake sure you have logged in with the other device.",
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  else
                    ...devices.map((device) {
                      return GestureDetector(
                        onTap: () async {
                          bool confirmed = await showConfirmDeleteDialog(
                                context,
                                title: "Confirm Device Selection",
                                message:
                                    "Do you want to select the device '${device['device_name']}' ?",
                              ) ??
                              false;

                          if (!confirmed) return;
                          Navigator.of(context).pop(device);
                          // Handle device selection
                          //print("Selected Device: ${device['device_name']}");
                        },
                        child: deviceCard(
                          context: context,
                          deviceName: device['device_name'] ?? 'Unknown Device',
                          deviceDetails:
                              device['owner_email'] ?? 'No details available',
                          iconData: Icons.devices,
                        ),
                      );
                    }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
