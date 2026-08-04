//
//  chat_search_query.dart
//
//  Token syntax for in-chat search: `from:` narrows to one sender, `has:`
//  narrows to one kind of message. Both map onto parameters TDLib's
//  searchChatMessages already takes — `sender_id` and `filter` — so a token is
//  a shorthand for a filter the search can genuinely apply, never a client-side
//  pass over results.
//
//  Deliberately absent: `mentions:<user>` and date ranges. TDLib can filter
//  mentions of the current user only, and searchChatMessages takes no date
//  bounds, so neither could be honoured.
//

import 'chat_message_search_controller.dart';

/// What a raw search field resolves to.
class ChatSearchTokens {
  const ChatSearchTokens({required this.text, this.fromQuery, this.filter});

  /// The query with every recognised token removed — what TDLib searches for.
  final String text;

  /// The text after `from:`, still to be resolved to a chat member.
  final String? fromQuery;

  /// The kind named by `has:`, when it named a supported one.
  final ChatSearchFilter? filter;

  bool get isEmpty => text.trim().isEmpty && fromQuery == null;
}

const _filterAliases = <String, ChatSearchFilter>{
  'link': ChatSearchFilter.links,
  'links': ChatSearchFilter.links,
  'url': ChatSearchFilter.links,
  'embed': ChatSearchFilter.links,
  'file': ChatSearchFilter.files,
  'files': ChatSearchFilter.files,
  'doc': ChatSearchFilter.files,
  'document': ChatSearchFilter.files,
  'photo': ChatSearchFilter.media,
  'image': ChatSearchFilter.media,
  'video': ChatSearchFilter.media,
  'media': ChatSearchFilter.media,
  'voice': ChatSearchFilter.voice,
  'music': ChatSearchFilter.music,
  'audio': ChatSearchFilter.music,
  'sound': ChatSearchFilter.music,
};

/// Kinds `has:` accepts, for anything that wants to describe the syntax.
Iterable<String> get chatSearchHasAliases => _filterAliases.keys;

final _tokenPattern = RegExp(
  // A token is `key:value`, where the value may be quoted to hold spaces.
  r'\b(from|has):("([^"]*)"|\S*)',
  caseSensitive: false,
);

/// Splits a raw field value into its search text and its tokens.
///
/// An unfinished token (`from:` with nothing after it) is dropped from the
/// search text but resolves to nothing, so results do not thrash while the
/// name is still being typed.
ChatSearchTokens parseChatSearchQuery(String raw) {
  String? fromQuery;
  ChatSearchFilter? filter;
  final text = raw
      .replaceAllMapped(_tokenPattern, (match) {
        final key = match.group(1)!.toLowerCase();
        final value = (match.group(3) ?? match.group(2) ?? '').trim();
        if (key == 'from') {
          if (value.isNotEmpty) fromQuery = value;
          return '';
        }
        final resolved = _filterAliases[value.toLowerCase()];
        // An unknown kind is not a filter; leave it in the text so the search
        // still looks for what was typed instead of silently ignoring it.
        if (resolved == null) return match.group(0)!;
        filter = resolved;
        return '';
      })
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return ChatSearchTokens(text: text, fromQuery: fromQuery, filter: filter);
}
