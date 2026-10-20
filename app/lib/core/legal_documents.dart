enum LegalDocumentType { privacy, terms }

class LegalDocument {
  const LegalDocument({
    required this.id,
    required this.type,
    required this.version,
    required this.title,
    required this.summary,
    required this.body,
    required this.updatedAt,
  });

  final String id;
  final LegalDocumentType type;
  final String version;
  final String title;
  final String summary;
  final String body;
  final DateTime updatedAt;

  factory LegalDocument.from(Map<String, dynamic> json) {
    final type = json['document_type'] == 'terms'
        ? LegalDocumentType.terms
        : LegalDocumentType.privacy;
    return LegalDocument(
      id: '${json['id'] ?? ''}',
      type: type,
      version: '${json['version'] ?? ''}'.trim(),
      title: '${json['title'] ?? ''}'.trim(),
      summary: '${json['summary'] ?? ''}'.trim(),
      body: '${json['content'] ?? ''}'.trim(),
      updatedAt: DateTime.tryParse('${json['updated_at'] ?? ''}')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  bool get isUsable =>
      version.isNotEmpty && title.isNotEmpty && body.isNotEmpty;
}
