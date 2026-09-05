  Future<void> _loadVideos() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final response = await TdClient.shared.query({
        '@type': 'searchChatMessages',
        'chat_id': widget.chat.id,
        'query': '',
        'sender_id': null,
        'from_message_id': 0,
        'offset': 0,
        'limit': 100,
        'filter': {'@type': 'searchMessagesFilterVideo'},
      });
      final videos = (response.objects('messages') ?? const [])
          .map(TDParse.message)
          .whereType<ChatMessage>()
          .where(
            (message) =>
                message.video != null &&
                (message.videoDuration ?? 0) > 0 &&
                message.videoDuration! <= _maxSeconds,
          )
          .toList();
      if (!mounted) return;
      setState(() {
        _videos = videos;
        _currentPage = 0;
        _loading = false;
      });
      _prefetchNextVideo(0);
      if (_pageController.hasClients) _pageController.jumpToPage(0);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }
