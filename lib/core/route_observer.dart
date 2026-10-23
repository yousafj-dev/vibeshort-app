import 'package:flutter/material.dart';

/// Shared route observer, registered on the MaterialApp in
/// main.dart. Feed video cards subscribe to their enclosing route
/// (RouteAware) so playback suspends while another page route
/// covers them — a pushed profile, hashtag page, the upload flow
/// and so on — and resumes when that route pops again. Bottom
/// sheets and dialogs are not page routes, so they never trigger
/// this (the video keeps playing behind the comments sheet, as
/// before).
final RouteObserver<PageRoute<dynamic>> appRouteObserver =
    RouteObserver<PageRoute<dynamic>>();
