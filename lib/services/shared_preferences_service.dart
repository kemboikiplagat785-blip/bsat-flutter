// import 'dart:async';

import 'package:bsat/utils/constants.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesService {
  final String offerChosen = "active_offer";
  final String runningStatus = "running_status";
  int sid = 2;

  // add uid to shared preferences
  Future<bool> setRunningStatus(bool isRunning) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setBool(runningStatus, isRunning);
      return true;
    } catch (e) {
      if (kDebugMode) {
        // //print(e.toString());
      }
    }

    return false;
  }

  // get uid from shared preferences
  Future<bool?> getRunningStatus() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    bool? uid = prefs.getBool(runningStatus);
    return uid;
    // return true;
  }

  Future<bool?> getCostAware() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    bool? uid = prefs.getBool(kSPCostAware);
    return uid;
  }

  Future<bool> setCostAware() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setBool(kSPCostAware, true);
      return true;
    } catch (e) {
      if (kDebugMode) {
        // //print(e.toString());
      }
    }
    // sid = id;

    return false;
  }

  Future<int?> getNextTaskDate() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    int? nextTaskDate = prefs.getInt("next-task-date");

    return nextTaskDate;
  }

  Future<bool> setNextTaskDate(int date, {int? sd}) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setInt("next-task-date", date).then((val) {
        // debugPrint("$val");
      });
      return true;
    } catch (e) {
      // if (kDebugMode) //print(e.toString());
    }

    return false;
  }

  Future<int?> getLastCheckSkippedTime() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    int? lastCheckSkippedTime = prefs.getInt("last-check-skipped-time");

    return lastCheckSkippedTime;
  }

  Future<bool> setLastCheckSkippedTime(int time) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setInt("last-check-skipped-time", time);
      return true;
    } catch (e) {
      // if (kDebugMode) //print(e.toString());
    }

    return false;
  }

  Future<String?> getRunningStatusStr() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    String? status = prefs.getString("running_status_str");
    return status;
  }

  Future<bool> setRunningStatusStr(String status) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setString("running_status_str", status);
      return true;
    } catch (e) {
      if (kDebugMode) {
        // //print(e.toString());
      }
    }
    return false;
  }

  Future<bool?> getAutoRenew() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    bool? autoRenew = prefs.getBool("auto_renew");
    return autoRenew;
  }

  Future<bool> setAutoRenew(bool autoRenew) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setBool("auto_renew", autoRenew);
      return true;
    } catch (e) {
      if (kDebugMode) {
        // //print(e.toString());
      }
    }
    return false;
  }

  Future<bool?> isSmsRunning() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    bool? paused = prefs.getBool("sms_running");
    // //print("isPaused: $paused");
    return paused;
  }

  Future<bool> setSmsRunning(bool paused) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setBool("sms_running", paused);
      return true;
    } catch (e) {
      // //print(e);
      // if (kDebugMode) {
      // }
    }
    return false;
  }

  Future<bool?> isDataRunning() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    bool? paused = prefs.getBool("data_running");
    // //print("isPaused: $paused");
    return paused;
  }

  Future<bool> setDataRunning(bool paused) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setBool("data_running", paused);
      return true;
    } catch (e) {
      // //print(e);
      // if (kDebugMode) {
      // }
    }
    return false;
  }

  Future<bool?> canAutoRetrySms() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    bool? canRetry = prefs.getBool("can_auto_retry_sms");
    return canRetry;
  }

  Future<bool> setCanAutoRetrySms(bool canRetry) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setBool("can_auto_retry_sms", canRetry);
      return true;
    } catch (e) {
      if (kDebugMode) {
        // //print(e.toString());
      }
    }
    return false;
  }

  Future<bool?> canAutoRetryData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    bool? canRetry = prefs.getBool("can_auto_retry_data");
    return canRetry;
  }

  Future<bool> setCanAutoRetryData(bool canRetry) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setBool("can_auto_retry_data", canRetry);
      return true;
    } catch (e) {
      if (kDebugMode) {
        // //print(e.toString());
      }
    }
    return false;
  }

  Future<int?> getDeliveryTokens() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    int? deliveryTokens = prefs.getInt("delivery_tokens");
    return deliveryTokens;
  }

  Future<bool> setDeliveryTokens(int tokens) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setInt("delivery_tokens", tokens);
      return true;
    } catch (e) {
      if (kDebugMode) {
        // //print(e.toString());
      }
    }
    return false;
  }

  Future<bool> setThemeMode(String themeMode) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setString("theme_mode", themeMode);
      return true;
    } catch (e) {
      if (kDebugMode) {
        // //print(e.toString());
      }
    }
    return false;
  }

  Future<String?> getThemeMode() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    String? themeMode = prefs.getString("theme_mode");
    return themeMode;
  }

  Future<String> getTransactionErrorStrings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    String errorStrings = prefs.getString("transaction_error_strings") ?? "";
    return errorStrings;
  }

  Future<bool> setTransactionErrorStrings(String errorStrings) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setString("transaction_error_strings", errorStrings);
      return true;
    } catch (e) {
      if (kDebugMode) {
        // //print(e.toString());
      }
    }
    return false;
  }

  Future<String> getTransactionSuccessStrings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    String successStrings =
        prefs.getString("transaction_success_strings") ?? "";
    return successStrings;
  }

  Future<bool> setTransactionSuccessStrings(String successStrings) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setString("transaction_success_strings", successStrings);
      return true;
    } catch (e) {
      if (kDebugMode) {
        // //print(e.toString());
      }
    }
    return false;
  }

  Future<String> getTransactionFailedStrings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    String failedStrings = prefs.getString("transaction_failed_strings") ?? "";
    return failedStrings;
  }

  Future<bool> setTransactionFailedStrings(String failedStrings) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setString("transaction_failed_strings", failedStrings);
      return true;
    } catch (e) {
      if (kDebugMode) {
        // //print(e.toString());
      }
    }
    return false;
  }

  Future<bool> setTransactionTimedOutStrings(String timedOutStrings) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setString("transaction_timed_out_strings", timedOutStrings);
      return true;
    } catch (e) {
      if (kDebugMode) {
        // //print(e.toString());
      }
    }
    return false;
  }

  Future<String> getTransactionTimedOutStrings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    String timedOutStrings =
        prefs.getString("transaction_timed_out_strings") ?? "";
    return timedOutStrings;
  }

  Future<bool> update() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    await setTransactionTimedOutStrings("connection code error|one minute");
    await setTransactionFailedStrings("already");
    // await setTransactionSuccessStrings("connection code error|one minute");
    await setTransactionErrorStrings(
        "error|duplicate|not available|unavailable|max number");

    return true;
  }

  Future<bool> setAutoSaveContacts(bool autoSave) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setBool("auto_save_contacts", autoSave);
      return true;
    } catch (e) {
      if (kDebugMode) {
        // //print(e.toString());
      }
    }
    return false;
  }

  Future<bool?> getAutoSaveContacts() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    bool? autoSave = prefs.getBool("auto_save_contacts");
    return autoSave;
  }

  Future<bool> setPostfixCOntactName(String name) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setString("postfix_contact_name", name);
      return true;
    } catch (e) {
      if (kDebugMode) {
        // //print(e.toString());
      }
    }
    return false;
  }

  Future<String?> getPostfixContactName() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    String? name = prefs.getString("postfix_contact_name");
    return name;
  }

  Future<bool> setRetryMinutes(int minutes) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setInt("retry_minutes", minutes);
      return true;
    } catch (e) {
      if (kDebugMode) {
        // //print(e.toString());
      }
    }
    return false;
  }

  Future<int?> getRetryMinutes() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    int? minutes = prefs.getInt("retry_minutes");
    return minutes;
  }

  Future<bool> setAppIsActiveState(bool state) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setBool("app_usage_state", state);
      return true;
    } catch (e) {
      if (kDebugMode) {
        // //print(e.toString());
      }
    }
    return false;
  }

  Future<bool?> getAppIsActiveState() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    bool? state = prefs.getBool("app_usage_state");
    return state;
  }

  Future<void> setOffersMightHaveChanged(bool state) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setBool("offers_might_have_changed", state);
    } catch (e) {
      if (kDebugMode) {
        // //print(e.toString());
      }
    }
  }

  Future<bool?> getOffersMightHaveChanged() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    bool? state = prefs.getBool("offers_might_have_changed");
    return state;
  }

  Future<bool> setAutoDeleteAfterNumberOfDays(int days) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setInt("auto_delete_after_number_of_days", days);
      return true;
    } catch (e) {
      if (kDebugMode) {
        // //print(e.toString());
      }
    }
    return false;
  }

  Future<int?> getAutoDeleteAfterNumberOfDays() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    int? days = prefs.getInt("auto_delete_after_number_of_days");
    return days;
  }

  // jwt_token
  Future<bool> setJwtToken(String token) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setString('jwt_token', token);
      return true;
    } catch (e) {
      if (kDebugMode) {
        // //print(e.toString());
      }
    }
    return false;
  }

  Future<String?> getJwtToken() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    String? token = prefs.getString('jwt_token');
    return token;
  }

  // user_id
  Future<bool> setUserId(String id) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setString('user_id', id);
      return true;
    } catch (e) {
      if (kDebugMode) {
        // //print(e.toString());
      }
    }
    return false;
  }

  Future<String?> getUserId() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    String? id = prefs.getString('user_id');
    return id;
  }

  // user_email
  Future<bool> setUserEmail(String email) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setString('user_email', email);
      return true;
    } catch (e) {
      if (kDebugMode) {
        // //print(e.toString());
      }
    }
    return false;
  }

  Future<String?> getUserEmail() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    String? email = prefs.getString('user_email');
    return email;
  }

  // user_name
  Future<bool> setUserName(String name) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setString('user_name', name);
      return true;
    } catch (e) {
      if (kDebugMode) {
        // //print(e.toString());
      }
    }
    return false;
  }

  Future<String?> getUserName() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    String? name = prefs.getString('user_name');
    return name;
  }

  // user_phone_number
  Future<bool> setPhoneNumber(String phoneNumber) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setString('user_phone_number', phoneNumber);
      return true;
    } catch (e) {
      if (kDebugMode) {
        // //print(e.toString());
      }
    }
    return false;
  }

  Future<String?> getPhoneNumber() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    String? phoneNumber = prefs.getString('user_phone_number');
    return phoneNumber;
  }

  // device_id
  Future<bool> setDeviceId(String deviceId) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setString('user_device_id', deviceId);
      return true;
    } catch (e) {
      if (kDebugMode) {
        // //print(e.toString());
      }
    }
    return false;
  }

  Future<String?> getDeviceId() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    String? deviceId = prefs.getString('user_device_id');
    return deviceId;
  }

  Future<bool> setDeviceName(String deviceName) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setString('user_device_name', deviceName);
      return true;
    } catch (e) {
      if (kDebugMode) {
        // //print(e.toString());
      }
    }
    return false;
  }

  Future<String?> getDeviceName() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    String? deviceName = prefs.getString('user_device_name');
    return deviceName;
  }

  // link extension
  Future<bool> setLinkExtension(String extension) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setString('user_link_extension', extension);
      return true;
    } catch (e) {
      if (kDebugMode) {
        // //print(e.toString());
      }
    }
    return false;
  }

  Future<String?> getLinkExtension() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    String? extension = prefs.getString('user_link_extension');
    return extension;
  }

  Future<bool?> getCanAutoSwitch() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    bool? autoSwitch = prefs.getBool("can_auto_switch");
    return autoSwitch;
  }

  Future<bool> setCanAutoSwitch(bool autoSwitch) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setBool("can_auto_switch", autoSwitch);
      return true;
    } catch (e) {
      if (kDebugMode) {
        // //print(e.toString());
      }
    }
    return false;
  }

  Future<bool?> getUseSignature() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    bool? useSignature = prefs.getBool("use_signature");
    return useSignature;
  }

  Future<bool?> setUseSignature(bool useSignature) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setBool("use_signature", useSignature);
      return true;
    } catch (e) {
      if (kDebugMode) {
        // //print(e.toString());
      }
    }
    return false;
  }

  Future<bool?> setForwardUnavailableLimit(int limit) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setInt("forward_unavailable_limit", limit);
      return true;
    } catch (e) {
      if (kDebugMode) {
        // //print(e.toString());
      }
    }
    return false;
  }

  Future<int?> getForwardUnavailableLimit() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    int? limit = prefs.getInt("forward_unavailable_limit");
    return limit;
  }

  Future<bool?> getForwardMaskedMessages() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    bool? forwardMasked = prefs.getBool("forward_masked_messages");
    return forwardMasked;
  }

  Future<bool> setForwardMaskedMessages(bool forwardMasked) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setBool("forward_masked_messages", forwardMasked);
      return true;
    } catch (e) {
      if (kDebugMode) {
        // //print(e.toString());
      }
    }
    return false;
  }

  // getAutoScheduleFailed
  Future<bool?> getAutoScheduleFailed() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    bool? autoScheduleFailed = prefs.getBool("auto_schedule_failed");
    return autoScheduleFailed;
  }

  Future<bool> setAutoScheduleFailed(bool autoScheduleFailed) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setBool("auto_schedule_failed", autoScheduleFailed);
      return true;
    } catch (e) {
      if (kDebugMode) {
        // //print(e.toString());
      }
    }
    return false;
  }

  Future<bool?> getDownloadOffers() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    bool? downloadOffers = prefs.getBool("download_offers");
    return downloadOffers;
  }

  Future<bool> setDownloadOffers(bool downloadOffers) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    try {
      await prefs.setBool("download_offers", downloadOffers);
      return true;
    } catch (e) {
      if (kDebugMode) {
        // //print(e.toString());
      }
    }
    return false;
  }

  Future<int?> getOnlineForwardingIndex(int amount) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getInt("online_forwarding_index_$amount");
  }

  Future<bool> setOnlineForwardingIndex(int amount, int index) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    try {
      return await prefs.setInt(
        "online_forwarding_index_$amount",
        index,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          "Failed to save online forwarding index for amount $amount: $e",
        );
      }
    }

    return false;
  }

  Future<Map<String, dynamic>> getAll() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    Set<String> keys = prefs.getKeys();
    Map<String, dynamic> settings = {};
    for (String key in keys) {
      settings[key] = prefs.get(key);
    }
    return settings;
  }

  Future<void> setAll(Map<String, dynamic> settings) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    for (var entry in settings.entries) {
      final value = entry.value;
      if (value is bool) {
        await prefs.setBool(entry.key, value);
      } else if (value is int) {
        await prefs.setInt(entry.key, value);
      } else if (value is double) {
        await prefs.setDouble(entry.key, value);
      } else if (value is String) {
        await prefs.setString(entry.key, value);
      } else if (value is List<String>) {
        await prefs.setStringList(entry.key, value);
      }
    }
  }

  void printAll() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    Set<String> keys = prefs.getKeys();
    for (String key in keys) {
      var value = prefs.get(key);
      print('$key: $value');
    }
  }
}
