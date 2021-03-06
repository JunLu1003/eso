import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:eso/api/api.dart';
import 'package:eso/api/api_manager.dart';
import 'package:eso/database/search_item_manager.dart';
import 'package:eso/model/profile.dart';
import 'package:flutter/services.dart';
import 'package:flutter_share/flutter_share.dart';
import 'package:intl/intl.dart' as intl;
import 'package:screen/screen.dart';
import '../database/search_item.dart';
import 'package:flutter/material.dart';

class MangaPageProvider with ChangeNotifier {
  final _format = intl.DateFormat('HH:mm:ss');
  Timer _timer;
  final SearchItem searchItem;
  List<String> _content;
  List<String> get content => _content;
  ScrollController _controller;
  ScrollController get controller => _controller;
  bool _isLoading;
  bool get isLoading => _isLoading;
  Map<String, String> _headers;
  Map<String, String> get headers => _headers;
  String _bottomTime;
  String get bottomTime => _bottomTime;
  bool _showChapter;
  bool get showChapter => _showChapter;

  set showChapter(bool value) {
    if (_showChapter != value) {
      _showChapter = value;
      notifyListeners();
    }
  }

  bool _showMenu;
  bool get showMenu => _showMenu;
  set showMenu(bool value) {
    if (_showMenu != value) {
      _showMenu = value;
      notifyListeners();
    }
  }

  bool _showSetting;
  bool get showSetting => _showSetting;
  set showSetting(bool value) {
    if (_showSetting != value) {
      _showSetting = value;
      notifyListeners();
    }
  }

  double _sysBrightness;
  double _brightness;
  double get brightness => _brightness;
  set brightness(double value) {
    if ((value - _brightness).abs() > 0.005) {
      _brightness = value;
      Screen.setBrightness(brightness);
    }
  }

  bool keepOn;
  void setKeepOn(bool value) {
    if (value != keepOn) {
      keepOn = value;
      Screen.keepOn(keepOn);
    }
  }

  bool landscape;
  void setLandscape(bool value) {
    if (value != landscape) {
      landscape = value;
      if (landscape) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeRight,
          DeviceOrientation.landscapeLeft,
        ]);
      } else {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      }
    }
  }

  int direction;
  void setDirection(int value) {
    if (value != direction) {
      direction = value;
      notifyListeners();
    }
  }

  MangaPageProvider({
    this.searchItem,
    this.keepOn = false,
    this.landscape = false,
    this.direction = Profile.mangaDirectionTopToBottom,
  }) {
    _brightness = 0.5;
    _bottomTime = _format.format(DateTime.now());
    _isLoading = false;
    _showChapter = false;
    _showMenu = false;
    _showSetting = false;
    _headers = Map<String, String>();
    _controller = ScrollController();
//    _controller.addListener(() {
//      if (_controller.position.pixels == _controller.position.maxScrollExtent) {
//        loadChapter(searchItem.durChapterIndex + 1);
//      }
//    });
    if (searchItem.chapters?.length == 0 &&
        SearchItemManager.isFavorite(searchItem.originTag, searchItem.url)) {
      searchItem.chapters = SearchItemManager.getChapter(searchItem.id);
    }
    _initContent();
  }

  void refreshProgress() {
    // searchItem.durContentIndex = _controller.position.pixels.floor();
    // notifyListeners();
  }

  void _initContent() async {
    if (Platform.isAndroid || Platform.isIOS) {
      _brightness = await Screen.brightness;
      if (_brightness > 1) {
        _brightness = 0.5;
      }
      _sysBrightness = _brightness;
      if (keepOn) {
        Screen.keepOn(keepOn);
      }
    }
    if (landscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeRight,
        DeviceOrientation.landscapeLeft,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
    await freshContentWithCache();
    notifyListeners();
  }

  void _setHeaders() {
    if (_content.length == 0) return;
    final first = _content[0].split('@headers');
    if (first.length == 1) return;
    _content[0] = first[0];
    _headers = (jsonDecode(first[1]) as Map).map((k, v) => MapEntry('$k', '$v'));
  }

  Map<int, List<String>> _cache;
  Future<bool> freshContentWithCache() async {
    final index = searchItem.durChapterIndex;

    /// 检查当前章节
    if (_cache == null) {
      _cache = {
        index: await APIManager.getContent(
          searchItem.originTag,
          searchItem.chapters[index].url,
        ),
      };
    } else if (_cache[index] == null) {
      _cache[index] = await APIManager.getContent(
        searchItem.originTag,
        searchItem.chapters[index].url,
      );
    }
    _content = _cache[index];
    _setHeaders();

    /// 缓存下一个章节
    if (index < searchItem.chapters.length - 1 && _cache[index + 1] == null) {
      Future.delayed(Duration(milliseconds: 100), () async {
        if (_cache[index + 1] == null) {
          _cache[index+1] = await APIManager.getContent(
            searchItem.originTag,
            searchItem.chapters[index+1].url,
          );
        }
      });
    }
    return true;
  }

  void share() async {
    await FlutterShare.share(
      title: '亦搜 eso',
      text:
          '${searchItem.name.trim()}\n${searchItem.author.trim()}\n\n${searchItem.description.trim()}\n\n${searchItem.url}',
      //linkUrl: '${searchItem.url}',
      chooserTitle: '选择分享的应用',
    );
  }

  bool _hideLoading = false;
  Future<void> loadChapterHideLoading(bool lastChapter) async {
    _showChapter = false;
    if (isLoading || _hideLoading) return;
    final loadIndex =
        lastChapter ? searchItem.durChapterIndex - 1 : searchItem.durChapterIndex + 1;
    if (loadIndex < 0 || loadIndex >= searchItem.chapters.length) return;
    _hideLoading = true;
    searchItem.durChapterIndex = loadIndex;
    await freshContentWithCache();
    searchItem.durChapter = searchItem.chapters[loadIndex].name;
    searchItem.durContentIndex = 1;
    searchItem.lastReadTime = DateTime.now().microsecondsSinceEpoch;
    await SearchItemManager.saveSearchItem();
    _hideLoading = false;
    if (searchItem.ruleContentType != API.RSS) {
      _controller.jumpTo(1);
    }
    notifyListeners();
  }

  Future<void> loadChapter(int chapterIndex) async {
    _showChapter = false;
    if (isLoading ||
        chapterIndex == searchItem.durChapterIndex ||
        chapterIndex < 0 ||
        chapterIndex >= searchItem.chapters.length) return;
    _isLoading = true;
    searchItem.durChapterIndex = chapterIndex;
    notifyListeners();
    await freshContentWithCache();
    searchItem.durChapter = searchItem.chapters[chapterIndex].name;
    searchItem.durContentIndex = 1;
    searchItem.lastReadTime = DateTime.now().microsecondsSinceEpoch;
    await SearchItemManager.saveSearchItem();
    _isLoading = false;
    if (searchItem.ruleContentType != API.RSS) {
      _controller.jumpTo(1);
    }
    notifyListeners();
  }

  bool get isFavorite => SearchItemManager.isFavorite(searchItem.originTag, searchItem.url);

  Future<bool> addToFavorite() async {
    if (isFavorite) return null;
    return await SearchItemManager.addSearchItem(searchItem);
  }

  Future<bool> removeFormFavorite() async {
    if (!isFavorite) return true;
    return await SearchItemManager.removeSearchItem(searchItem.id);
  }

  void refreshCurrent() async {
    if (isLoading) return;
    _isLoading = true;
    _showChapter = false;
    notifyListeners();
    _content = await APIManager.getContent(
        searchItem.originTag, searchItem.chapters[searchItem.durChapterIndex].url);
    searchItem.lastReadTime = DateTime.now().microsecondsSinceEpoch;
    _isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    if (Platform.isAndroid || Platform.isIOS) {
      if (Platform.isAndroid) {
        Screen.setBrightness(-1.0);
      } else {
        Screen.setBrightness(_sysBrightness);
      }
      Screen.keepOn(false);
    }
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _timer?.cancel();
    content.clear();
    _controller.dispose();
    searchItem.lastReadTime = DateTime.now().microsecondsSinceEpoch;
    _cache.clear();
    SearchItemManager.saveSearchItem();
    super.dispose();
  }
}
