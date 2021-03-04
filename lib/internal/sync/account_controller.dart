import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:loggy/loggy.dart';
import 'package:potato_notes/internal/providers.dart';
import 'package:potato_notes/internal/sync/image/image_helper.dart';
import 'package:potato_notes/internal/sync/sync_routine.dart';

class AccountController {
  AccountController._();

  // used for registering a user, all it needs is username, email, password.
  // When there is an error it throws an exception which needs to be catched
  static Future<AuthResponse> register(
      String username, String email, String password) async {
    final Map<String, String> body = {
      "username": username,
      "email": email,
      "password": password,
    };
    try {
      final Response registerResponse = await dio.post(
        "${prefs.apiUrl}/login/user/register",
        data: json.encode(body),
        options: Options(
          headers: {"Content-Type": "application/json"},
        ),
      );
      Loggy.v(
        message:
            "(register) Server responded with (${registerResponse.statusCode}): ${registerResponse.data}",
        secure: true,
      );

      switch (registerResponse.statusCode) {
        case 200:
          return AuthResponse(status: true);
        default:
          return AuthResponse(
            status: false,
            message: registerResponse.data,
          );
      }
    } on SocketException {
      return AuthResponse(
        status: false,
        message: "Could not connect to auth server",
      );
    } catch (e) {
      return AuthResponse(
        status: false,
        message: e.toString(),
      );
    }
  }

  // Logs in the user and puts tokens in shared_prefs
  // When there is an error it throws an exception which needs to be catched
  static Future<AuthResponse> login(String emailOrUser, String password) async {
    Map<String, String> body;

    if (emailOrUser.contains(RegExp(".*\..*@.*\..*", dotAll: true))) {
      body = {
        "email": emailOrUser,
        "password": password,
      };
    } else {
      body = {
        "username": emailOrUser,
        "password": password,
      };
    }

    try {
      final Response loginResponse = await dio.post(
        "${prefs.apiUrl}/login/user/login",
        data: json.encode(body),
        options: Options(
          headers: {"Content-Type": "application/json"},
        ),
      );
      Loggy.v(
        message:
            "(login) Server responded with (${loginResponse.statusCode}): ${loginResponse.data}",
        secure: true,
      );
      switch (loginResponse.statusCode) {
        case 200:
          final Map<String, dynamic> response = loginResponse.data;
          prefs.accessToken = response["token"];
          prefs.refreshToken = response["refresh_token"];
          await getUserInfo();
          return AuthResponse(status: true);
        default:
          Loggy.d(message: loginResponse.data);
          return AuthResponse(
            status: false,
            message: loginResponse.data,
          );
          break;
      }
    } on SocketException {
      throw ("Could not connect to server");
    } catch (e) {
      rethrow;
    }
  }

  static Future<AuthResponse> getUserInfo() async {
    final bool loggedIn = await SyncRoutine.checkLoginStatus();

    if (loggedIn) {
      final String token = await prefs.getToken();

      try {
        final Response profileRequest = await dio.get(
          "${prefs.apiUrl}/login/user/profile",
          options: Options(
            headers: {"Authorization": "Bearer " + token},
          ),
        );
        switch (profileRequest.statusCode) {
          case 200:
            final Map<String, dynamic> response = profileRequest.data;
            prefs.username = response["username"];
            prefs.email = response["email"];
            prefs.avatarUrl = await ImageHelper.getAvatar(token);
            return AuthResponse(status: true);
          case 400:
            return AuthResponse(
              status: false,
              message: profileRequest.data,
            );
          default:
            throw ("Unexpected response from auth server");
        }
      } on SocketException {
        throw ("Could not connect to server");
      } catch (e) {
        rethrow;
      }
    } else {
      return AuthResponse(status: false, message: "Not logged in.");
    }
  }

  static Future<void> logout() async {
    prefs.accessToken = null;
    prefs.refreshToken = null;
    prefs.username = null;
    prefs.email = null;
    prefs.lastUpdated = 0;
    prefs.avatarUrl = null;

    await tagHelper.deleteAllTags();
    await helper.deleteAllNotes();
  }

  // When the api the app uses returns a 401 (Unauthorized) this likely means the token is expired and needs to be refreshed
  // If the refreshing returns an exception with the body, it means it couldnt request access again
  // This means that the user needs to log back in.
  // When there is an error it throws an exception which needs to be catched
  static Future<AuthResponse> refreshToken() async {
    Response refresh;

    if (prefs.refreshToken == null)
      return AuthResponse(status: false, message: "Not logged in");

    try {
      final String url = "${prefs.apiUrl}/login/user/refresh";
      Loggy.v(message: "Going to send GET to " + url);
      refresh = await dio.get(
        url,
        options: Options(
          headers: {"Authorization": "Bearer ${prefs.refreshToken}"},
        ),
      );
      Loggy.v(
        message:
            "(refreshToken) Server responded with (${refresh.statusCode}): ${refresh.data}",
        secure: true,
      );
      switch (refresh.statusCode) {
        case 200:
          {
            prefs.accessToken = refresh.data["token"];
            Loggy.d(message: "accessToken: " + prefs.accessToken, secure: true);
            return AuthResponse(status: true);
          }
        case 400:
          return AuthResponse(
            status: false,
            message: refresh.data,
          );
        default:
          throw ("Unexpected response from auth server");
      }
    } on SocketException {
      throw ("Could not connect to server");
    } catch (e) {
      rethrow;
    }
  }
}

class AuthResponse {
  final bool status;
  final String message;

  AuthResponse({
    @required this.status,
    this.message,
  });
}
