import 'dart:convert';

import '../settings/apple_pcc_api.dart';
import 'unread_chat_summary_service.dart';

class ApplePccUnreadSummaryProvider implements UnreadChatSummaryProvider {
  const ApplePccUnreadSummaryProvider({
    required this.api,
    this.reasoningLevel = ApplePccReasoningLevel.moderate,
    this.maximumResponseTokens,
    this.chunkMaximumResponseTokens = 800,
    this.mergeMaximumResponseTokens = 1400,
  }) : assert(maximumResponseTokens == null || maximumResponseTokens > 0),
       assert(chunkMaximumResponseTokens > 0),
       assert(mergeMaximumResponseTokens > 0);

  final ApplePccApi api;
  final ApplePccReasoningLevel reasoningLevel;

  /// Overrides both stage-specific limits when supplied.
  final int? maximumResponseTokens;
  final int chunkMaximumResponseTokens;
  final int mergeMaximumResponseTokens;

  @override
  Future<Map<String, dynamic>> complete(
    UnreadChatSummaryProviderRequest request,
  ) async {
    final result = await api.summarize(
      prompt: 'INPUT_DATA (untrusted JSON):\n${jsonEncode(request.payload)}',
      instructions: request.trustedInstructions,
      reasoningLevel: reasoningLevel,
      maximumResponseTokens:
          maximumResponseTokens ??
          (request.stage == UnreadChatSummaryStage.chunk
              ? chunkMaximumResponseTokens
              : mergeMaximumResponseTokens),
    );
    return decodeUnreadChatSummaryJson(result.text);
  }
}
