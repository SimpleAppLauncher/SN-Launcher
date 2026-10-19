import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';


/// Radio stations the launcher can actually play.
///
/// **Why radio and not YouTube.** This is the whole point of the list. The
/// card is not a decoration over a WebView — it drives a real Android media
/// player, and the only things that player can play are media URLs. A YouTube
/// page is not one: extracting a stream URL from it breaches YouTube's
/// Developer Policies and defeats their signature cipher, and the WebView
/// that used to sit behind the button cannot play audio once the screen
/// locks. A radio stream is a plain HTTP media URL, free to play, and it keeps
/// going with the app closed.
///
/// **The stations are SomaFM's**, which publish their streams under Creative
/// Commons and do not restrict redistribution to their own player. Each one
/// is a plain Icecast MP3 endpoint.
///
/// **They need a browser User-Agent.** SomaFM's servers reject the default
/// one, and a stream that returns no bytes looks exactly like a dead link.
/// That cost an hour to find.
class RadioStation {
  const RadioStation({
    required this.id,
    required this.name,
    required this.blurb,
    required this.streamUrl,
  });

  final String id;
  final String name;
  final String blurb;
  final String streamUrl;

  /// SomaFM publishes what is playing right now as JSON.
  String get songInfoUrl => 'https://somafm.com/songinfo/$id.json';
}

/// The stations. Curated rather than exhaustive: eight is enough to prove the
/// feature and few enough to stay out of the way.
const List<RadioStation> kRadioStations = [
  RadioStation(
    id: 'groovesalad',
    name: 'Groove Salad',
    blurb: 'Ambient downtempo',
    streamUrl: 'https://ice1.somafm.com/groovesalad-128-mp3',
  ),
  RadioStation(
    id: 'dronezone',
    name: 'Drone Zone',
    blurb: 'Atmospheric textures',
    streamUrl: 'https://ice2.somafm.com/dronezone-128-mp3',
  ),
  RadioStation(
    id: 'u80s',
    name: ' Underground 80s',
    blurb: 'Early alternative and new wave',
    streamUrl: 'https://ice1.somafm.com/u80s-128-mp3',
  ),
  RadioStation(
    id: 'sonicuniverse',
    name: 'Sonic Universe',
    blurb: 'Avant-garde jazz and electronica',
    streamUrl: 'https://ice1.somafm.com/sonicuniverse-128-mp3',
  ),
  RadioStation(
    id: 'indiepop',
    name: 'Indie Pop Rocks',
    blurb: 'Indie and alternative pop',
    streamUrl: 'https://ice1.somafm.com/indiepop-128-mp3',
  ),
  RadioStation(
    id: 'secretagent',
    name: 'Secret Agent',
    blurb: 'Spy jazz for your kitchen',
    streamUrl: 'https://ice1.somafm.com/secretagent-128-mp3',
  ),
  RadioStation(
    id: 'beatblender',
    name: 'Beat Blender',
    blurb: 'A late-night blend of beats',
    streamUrl: 'https://ice1.somafm.com/beatblender-128-mp3',
  ),
  RadioStation(
    id: 'lush',
    name: 'Lush Vocal',
    blurb: 'Mostly vocals, mostly chilled',
    streamUrl: 'https://ice1.somafm.com/lush-128-mp3',
  ),
];

/// A station, plus whatever is currently playing on it.
@immutable
class NowPlaying {
  const NowPlaying({
    required this.station,
    this.artist = '',
    this.title = '',
  });

  final RadioStation station;
  final String artist;
  final String title;

  /// What to put on the card.
  ///
  /// A live radio stream has no "duration", so the card must not show one —
  /// and the track line shows the artist and title when the station tells us,
  /// and the station name when it does not. Never a blank.
  String get displayTitle {
    if (title.isNotEmpty) return title;
    return station.name;
  }

  String get displayArtist {
    if (artist.isNotEmpty) return artist;
    return station.blurb;
  }
}

/// Looks up what is playing on a station.
class RadioNowPlaying {
  static Future<NowPlaying?> fetch(RadioStation station) async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      try {
        final request = await client.getUrl(Uri.parse(station.songInfoUrl));
        request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
        final response = await request.close();
        if (response.statusCode != 200) return null;
        final body = await response.transform(utf8.decoder).join();
        final decoded = jsonDecode(body);
        if (decoded is! Map) return null;
        final songs = decoded['songs'];
        if (songs is! List || songs.isEmpty) return null;
        final first = songs.first;
        if (first is! Map) return null;
        return NowPlaying(
          station: station,
          artist: first['artist'] is String ? first['artist'] as String : '',
          title: first['title'] is String ? first['title'] as String : '',
        );
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      // A station that will not say what it is playing is still a station we
      // can play. The card shows the station name, which is honest.
      return null;
    }
  }

  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0.0.0 Mobile Safari/537.36';
}
