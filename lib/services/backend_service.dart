import 'dart:convert';
import 'package:bsat/services/auth_service.dart';
import 'package:bsat/utils/logger.dart';
import 'package:http/http.dart' as http;

class BackendService {
  final AuthService _authService = AuthService();
  final String baseUrl = 'https://api.bsat.co.ke'; // Same as AuthService
  final _log = BsatLogger(tag: 'BackendService');

  /// Generic GET request
  Future<Map<String, dynamic>> get(String endpoint) async {
    _log.info('GET request', endpoint);
    try {
      final response = await _authService.authenticatedRequest(
        endpoint: endpoint,
        method: 'GET',
      );

      return _handleResponse(response, 'GET $endpoint');
    } catch (e) {
      _log.error('GET request failed', e);
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  /// Generic POST request
  Future<Map<String, dynamic>> post(String endpoint, {Map<String, dynamic>? body}) async {
    _log.info('POST request to $endpoint', body);
    try {
      final response = await _authService.authenticatedRequest(
        endpoint: endpoint,
        method: 'POST',
        body: body,
      );

      return _handleResponse(response, 'POST $endpoint');
    } catch (e) {
      _log.error('POST request failed', e);
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  /// Generic PUT request
  Future<Map<String, dynamic>> put(String endpoint, {Map<String, dynamic>? body}) async {
    _log.info('PUT request to $endpoint', body);
    try {
      final response = await _authService.authenticatedRequest(
        endpoint: endpoint,
        method: 'PUT',
        body: body,
      );

      return _handleResponse(response, 'PUT $endpoint');
    } catch (e) {
      _log.error('PUT request failed', e);
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  /// Generic DELETE request
  Future<Map<String, dynamic>> delete(String endpoint) async {
    _log.info('DELETE request', endpoint);
    try {
      final response = await _authService.authenticatedRequest(
        endpoint: endpoint,
        method: 'DELETE',
      );

      return _handleResponse(response, 'DELETE $endpoint');
    } catch (e) {
      _log.error('DELETE request failed', e);
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  /// Handle HTTP responses and decode JSON
  Map<String, dynamic> _handleResponse(http.Response response, String context) {
    try {
      final body = jsonDecode(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _log.debug('$context success', {'status': response.statusCode});
        return {
          'success': true,
          'data': body,
          'statusCode': response.statusCode,
        };
      } else {
        _log.warn('$context failed', {
          'status': response.statusCode,
          'body': body
        });
        return {
          'success': false,
          'message': body['message'] ?? 'Request failed',
          'error': body,
          'statusCode': response.statusCode,
        };
      }
    } catch (e) {
      _log.error('$context - Failed to parse response', {'body': response.body, 'error': e});
      return {
        'success': false,
        'message': 'Failed to parse response: ${response.body}',
        'statusCode': response.statusCode,
      };
    }
  }

  // Example: Send a message via the backend (if your API supports it)
  Future<Map<String, dynamic>> sendMessage({
    required String title,
    required String body,
    String? topic,
  }) async {
    return await post('/api/fcm/send', body: {
      'title': title,
      'body': body,
      'topic': topic ?? 'general',
    });
  }

  // Example: Get user transactions
  Future<Map<String, dynamic>> getTransactions() async {
    return await get('/api/transactions');
  }
}
