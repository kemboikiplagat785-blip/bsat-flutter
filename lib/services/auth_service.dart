import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:bsat/services/shared_preferences_service.dart';

class AuthService {
  final String baseUrl = 'https://bsat.co.ke'; // Replace with your API URL
  final SharedPreferencesService _prefs = SharedPreferencesService();

  // ping to check if phone is online
  Future<bool> pingServer() async {
    try {
      final response = await http.get(
        Uri.parse('https://google.com'),
        headers: {'Content-Type': 'application/json'},
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Signup with email and password
  Future<Map<String, dynamic>> signup({
    required String email,
    required String password,
    required String name,
    required String linkExtension,
  }) async {
    try {
      //print everything
      //print('Email: $email');
      //print('Name: $name');
      //print('Password: $password');
      //print('Link Extension: $linkExtension');
      //print("url: $baseUrl/api/auth/register");

      // check if linkExtension contains spaces and remove them
      linkExtension = linkExtension.replaceAll(' ', '');
      //reove other special characters except _ and -
      linkExtension = linkExtension.replaceAll(RegExp(r'[^\w\-]'), '');


      final linkAvailable = await getLinkAvailable(linkExtension);
      if (!linkAvailable['success']) {
        return {
          'success': false,
          'message': linkAvailable['message'] ?? 'Link extension is already taken',
        };
      }

      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'name': name,
          'linkExtension': linkExtension,
        }),
      );

      //print('Response status: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);

        // Save JWT token
        if (data['token'] != null) {
          await _prefs.setJwtToken(data['token']);
          await _prefs.setUserEmail(email);
          await _prefs.setUserName(name);
          await _prefs.setLinkExtension(linkExtension);
          if (data['user'] != null) {
            await _prefs.setUserId(data['user']['id']?.toString() ?? '');
          }
        }

        return {
          'success': true,
          'message': 'Account created successfully',
          'data': data,
        };
      } else {
        final error = jsonDecode(response.body);
        // final error = response.body;
        return {
          'success': false,
          // 'message': error,
          'message': error['message'] ?? 'Signup failed',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> getLinkAvailable(String linkExtension) async {
    try {
      final response = await http.get(
        Uri.parse(
            '$baseUrl/api/auth/check-link-extension-availability/$linkExtension'),
        headers: {'Content-Type': 'application/json'},
      );

      print('Link Availability Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': 'Link is available',
        };
      } else if (response.statusCode == 409) {
        return {
          'success': false,
          'message': response.body,
        };
      }
    } catch (e) {
      // debugPrint('Error checking link availability: ${e.toString()}');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
    return {
      'success': false,
      'message': 'Error. Could not check link availability',
    };
  }

  // app.put('/api/auth/update-link-extension'
  Future<Map<String, dynamic>> updateLinkExtension({
    required String newLinkExtension,
  }) async {
    try {
      var jwtToken = await getToken();

      if (jwtToken == null || jwtToken.isEmpty) {
        //print('No JWT token available');
        return {
          'success': false,
          'message': 'No JWT token available',
        };
      }

      final linkAvailable = await getLinkAvailable(newLinkExtension);
      if (!linkAvailable['success']) {
        return {
          'success': false,
          'message': linkAvailable['message'] ?? 'Link extension is already taken',
        };
      }

      final response = await http.put(
        Uri.parse('$baseUrl/api/auth/update-link-extension'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
        body: jsonEncode({
          'newLinkExtension': newLinkExtension,
        }),
      );

      print(response.body);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _prefs.setLinkExtension(newLinkExtension);
        return {
          'success': true,
          'data': data,
        };
      } else {
        final error = jsonDecode(response.body);
        return {
          'success': false,
          'message': error['message'] ?? 'Failed to update link extension',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> isDeviceRegisteredToMe() async {
    try {
      var jwtToken = await getToken();

      if (jwtToken == null || jwtToken.isEmpty) {
        //print('No JWT token available');
        return {
          'success': false,
          'message': 'No JWT token available',
        };
      }

      var deviceInfo = await DeviceInfoPlugin().androidInfo;

      final response = await http.post(
        Uri.parse('$baseUrl/api/device/isregistered'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
        body: jsonEncode({
          'deviceId': deviceInfo.id,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'data': data,
        };
      } else {
        final error = jsonDecode(response.body);
        return {
          'success': false,
          'message': error['message'] ?? 'Failed to check device registration',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // register device info
  // user_id, device_name, device_id, model, android_version, created_at
  Future<void> registerDeviceInfo({String? name}) async {
    try {
      var jwtToken = await getToken();

      if (jwtToken == null || jwtToken.isEmpty) {
        //print('No JWT token available');
        return;
      }

      var deviceInfo = await DeviceInfoPlugin().androidInfo;

      final userInfo = await getUserInfo();
      final userId = userInfo['id'] ?? '';

      //print('Registering device info: ${jsonEncode({
          //   'userId': userId,
          //   'deviceName': name ?? deviceInfo.device,
          //   'deviceId': deviceInfo.id,
          //   'model': deviceInfo.model,
          //   'androidVersion': deviceInfo.version.release,
          // })}');

      final response = await http.post(
        Uri.parse('$baseUrl/api/device/register'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
        body: jsonEncode({
          'deviceName': name ?? deviceInfo.device,
          'deviceId': deviceInfo.id,
          'model': deviceInfo.model,
          'androidVersion': deviceInfo.version.release,
          'createdAtMillis': DateTime.now().millisecondsSinceEpoch,
          // 'created_at_millis': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        await _prefs.setDeviceId(deviceInfo.id);
      } else if (response.statusCode == 409) {
        // Device already registered
        //print('Device already registered. changing owner');

        await http.post(
          Uri.parse('$baseUrl/api/device/changeowner'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $jwtToken',
          },
          body: jsonEncode({
            'deviceId': deviceInfo.id,
            'newOwnerId': userId,
          }),
        );

        await _prefs.setDeviceId(deviceInfo.id);
      } else {
        //print('Failed to register device info, status: ${response.body}');
      }
    } catch (e) {
      //print('Error registering device info: ${e.toString()}');
    }
  }

  // search for device using email, id or name
  Future<Map<String, dynamic>> searchDevice({
    required String query,
  }) async {
    try {
      var jwtToken = await getToken();

      //print(jwtToken);

      if (jwtToken == null || jwtToken.isEmpty) {
        //print('No JWT token available');
        return {
          'success': false,
          'message': 'No JWT token available',
        };
      }

      final response = await http.get(
        Uri.parse('$baseUrl/api/device/search?query=$query'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
      );

      //print('Search Device Response status: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'data': data,
        };
      } else {
        final error = jsonDecode(response.body);
        return {
          'success': false,
          'message': error['message'] ?? 'Failed to search device',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // get whitelisted devices
  Future<Map<String, dynamic>> getWhitelistedDevices() async {
    try {
      var jwtToken = await getToken();

      if (jwtToken == null || jwtToken.isEmpty) {
        //print('No JWT token available');
        return {
          'success': false,
          'message': 'No JWT token available',
        };
      }

      final response = await http.get(
        Uri.parse('$baseUrl/api/device/whitelisted'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'data': data,
        };
      } else {
        final error = jsonDecode(response.body);
        return {
          'success': false,
          'message': error['message'] ?? 'Failed to get whitelisted devices',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Login with email and password
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      //print('Response status: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Save JWT token and user info
        if (data['token'] != null) {
          await _prefs.setJwtToken(data['token']);
          await _prefs.setUserEmail(email);

          if (data['user'] != null) {
            await _prefs.setUserName(data['user']['name'] ?? '');
            await _prefs.setUserId(data['user']['id']?.toString() ?? '');
            await _prefs.setLinkExtension(data['user']['linkExtension'] ?? '');
          }
        }

        return {
          'success': true,
          'message': 'Login successful',
          'data': data,
        };
      } else {
        final error = jsonDecode(response.body);
        return {
          'success': false,
          'message': error['message'] ?? 'Invalid credentials',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> requestOTP({
    required String email,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/send-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
        }),
      );

      print('Response status: ${response.body}, uri: $baseUrl/api/auth/send-otp');

      if (response.statusCode == 200) {
        //print('OTP requested successfully');
        return {
          'success': true,
          'message': 'OTP sent successfully',
        };
      } else {
        //print('Failed to request OTP, status: ${response.body}');
        final error = jsonDecode(response.body);
        return {
          'success': false,
          'message': error['error'] ?? 'Failed to send OTP',
        };
      }
    } catch (e) {
      //print('Error requesting OTP: ${e.toString()}');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // verify OTP
  Future<Map<String, dynamic>> verifyOTP({
    required String email,
    required String otp,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/verify-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'otp': otp,
        }),
      );

      //print('Response status: ${response.body}');

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': 'OTP verified successfully',
        };
      } else {
        final error = jsonDecode(response.body);
        return {
          'success': false,
          'message': error['error'] ?? 'Invalid OTP',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Reset password
  Future<Map<String, dynamic>> resetPassword({
    required String newPassword,
    required String email,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'newPassword': newPassword,
          'email': email,
        }),
      );

      //print('Response status: ${response.body}');

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': 'Password reset successfully',
        };
      } else {
        final error = jsonDecode(response.body);
        return {
          'success': false,
          'message': error['message'] ?? 'Failed to reset password',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

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

  // get offers from table
  // app.get('/api/offers/:linkExtension',
  Future<Map<String, dynamic>> getOffers({
    required String linkExtension,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/offers/$linkExtension'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'data': data,
        };
      } else {
        final error = jsonDecode(response.body);
        return {
          'success': false,
          'message': error['message'] ?? 'Failed to get offer',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // post/update online data
  Future<Map<String, dynamic>> createOnlineOffer(
    String linkExtension,
    Map<String, dynamic> offerData,
  ) async {
    try {
      var jwtToken = await getToken();

      if (jwtToken == null || jwtToken.isEmpty) {
        //print('No JWT token available');
        return {
          'success': false,
          'message': 'No JWT token available',
        };
      }

      final response = await http.post(
        Uri.parse('$baseUrl/api/offers/create'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
        body: jsonEncode({
          'linkExtension': linkExtension,
          'offerData': offerData,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'data': data,
        };
      } else {
        final error = jsonDecode(response.body);
        //print(response.body);
        return {
          'success': false,
          'message': error['message'] ?? 'Failed to update offer',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> updateOnlineOffer(
    int offerId,
    Map<String, dynamic> offerData,
  ) async {
    try {
      var jwtToken = await getToken();

      if (jwtToken == null || jwtToken.isEmpty) {
        //print('No JWT token available');
        return {
          'success': false,
          'message': 'No JWT token available',
        };
      }

      final response = await http.post(
        Uri.parse('$baseUrl/api/offers/update/$offerId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
        body: jsonEncode({
          'offerData': offerData,
        }),
      );

      //print('Update Response status: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'data': data,
        };
      } else {
        final error = jsonDecode(response.body);
        return {
          'success': false,
          'message': error['message'] ?? 'Failed to update offer',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> deleteOnlineOffer(
    int id,
  ) async {
    try {
      var jwtToken = await getToken();

      if (jwtToken == null || jwtToken.isEmpty) {
        //print('No JWT token available');
        return {
          'success': false,
          'message': 'No JWT token available',
        };
      }

      final response = await http.delete(
        Uri.parse('$baseUrl/api/offers/delete/$id'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
      );

      //print('Delete Response status: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'data': data,
        };
      } else {
        final error = jsonDecode(response.body);
        return {
          'success': false,
          'message': error['message'] ?? 'Failed to delete offer',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  Future<void> logout() async {
    await _prefs.setJwtToken("");
    await _prefs.setUserEmail("");
    await _prefs.setUserName("");
    await _prefs.setUserId("");
    await _prefs.setDeviceId("");
    await _prefs.setLinkExtension("");
  }

  // Check if user is logged in
  Future<bool> isLoggedIn() async {
    final token = await _prefs.getJwtToken();
    return token != null && token.isNotEmpty;
  }

  // Get stored JWT token
  Future<String?> getToken() async {
    return await _prefs.getJwtToken();
  }

  // Get user info
  Future<Map<String, String?>> getUserInfo() async {
    return {
      'email': await _prefs.getUserEmail(),
      'name': await _prefs.getUserName(),
      'id': await _prefs.getUserId(),
    };
  }

  // // Get device info from deviceinfoplugin
  // Future<Map<String, dynamic>> getDeviceInfo() async {
  //   // Implement device info retrieval if needed
  //   var deviceInfo = await DeviceInfoPlugin().androidInfo;
  //   return {};
  // }

  // Verify token (optional - check with backend)
  Future<bool> verifyToken() async {
    try {
      final token = await getToken();
      if (token == null) return false;

      final response = await http.get(
        Uri.parse('$baseUrl/api/auth/verify-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Make authenticated requests
  Future<http.Response> authenticatedRequest({
    required String endpoint,
    required String method,
    Map<String, dynamic>? body,
  }) async {
    final token = await getToken();

    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    final uri = Uri.parse('$baseUrl$endpoint');

    switch (method.toUpperCase()) {
      case 'GET':
        return await http.get(uri, headers: headers);
      case 'POST':
        return await http.post(uri, headers: headers, body: jsonEncode(body));
      case 'PUT':
        return await http.put(uri, headers: headers, body: jsonEncode(body));
      case 'DELETE':
        return await http.delete(uri, headers: headers);
      default:
        throw Exception('Unsupported HTTP method: $method');
    }
  }
}
