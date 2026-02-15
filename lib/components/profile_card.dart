import 'package:bsat/utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class ProfileCard extends StatelessWidget {
  final String name;
  final String email;
  final String webLink;
  final int numberOfDevices;

  const ProfileCard({
    super.key,
    required this.name,
    required this.email,
    required this.webLink,
    required this.numberOfDevices,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: kPagePaddingInsets,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(kBorderRadius),
        border: Border(
          right: BorderSide(
            color: kIndigoColor,
            width: 4.0,
          ),
          bottom: BorderSide(
            color: kIndigoColor,
            width: 4.0,
          ),
        ),
        image: const DecorationImage(
          image: AssetImage('assets/images/mesh_distorted.png'),
          alignment: Alignment.centerLeft,
          fit: BoxFit.cover,
          opacity: 0.1,
        ),
        // Optional: Add shadow if needed to match other cards
        // boxShadow: [
        //   BoxShadow(
        //     color: Colors.black.withOpacity(0.05),
        //     blurRadius: 10,
        //     offset: const Offset(0, 4),
        //   ),
        // ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: kIndigoColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Image.asset(
              'assets/icons/icon.png',
              width: 40.0,
              height: 40.0,
              color: kIndigoColor,
            ),
          ),
          const SizedBox(width: kPagePadding),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18.0,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 14.0,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final Uri url = Uri.parse(webLink);
                          if (await canLaunchUrl(url)) {
                            await launchUrl(url,
                                mode: LaunchMode.externalApplication);
                          }
                        },
                        child: Text(
                          webLink,
                          style: const TextStyle(
                            color: kIndigoColor,
                            fontSize: 14.0,
                            decoration: TextDecoration.underline,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: webLink));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Link copied to clipboard"),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      child: const Icon(
                        Icons.copy,
                        size: 16.0,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Row(
                //   children: [
                //     const Icon(
                //       Icons.devices_other,
                //       size: 16.0,
                //       color: kDullColor,
                //     ),
                //     const SizedBox(width: 4),
                //     Text(
                //       "$numberOfDevices Active Devices",
                //       style: const TextStyle(
                //         color: kDullColor,
                //         fontSize: 12.0,
                //       ),
                //     ),
                //   ],
                // ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
