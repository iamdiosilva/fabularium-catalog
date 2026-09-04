class CommunitySubmission {
  final String id;
  final String submittedBy;
  final String name;
  final String? studio;
  final String? category;
  final String? type;
  final String? scale;
  final String? height;
  final String? description;
  final List<String> tags;
  final String status;
  final String duplicateStatus;
  final String? duplicateOfModelId;
  final String? archiveFileName;
  final int archiveSize;
  final String? archiveSha256;
  final String? contentFingerprint;
  final String? storageKey;
  final String? uploadError;
  final DateTime submittedAt;
  final DateTime? uploadedAt;
  final DateTime? reviewedAt;
  final String? reviewNote;

  const CommunitySubmission({
    required this.id,
    required this.submittedBy,
    required this.name,
    required this.studio,
    required this.category,
    required this.type,
    required this.scale,
    required this.height,
    required this.description,
    required this.tags,
    required this.status,
    required this.duplicateStatus,
    required this.duplicateOfModelId,
    required this.archiveFileName,
    required this.archiveSize,
    required this.archiveSha256,
    required this.contentFingerprint,
    required this.storageKey,
    required this.uploadError,
    required this.submittedAt,
    required this.uploadedAt,
    required this.reviewedAt,
    required this.reviewNote,
  });

  bool get isUploading =>
      status == 'uploading';

  bool get isUploaded =>
      status == 'uploaded';

  bool get isProcessing =>
      status == 'processing';

  bool get isPendingReview =>
      status == 'pending_review' ||
      status == 'duplicate_suspected';

  bool get isApproved =>
      status == 'approved' ||
      status == 'publishing' ||
      status == 'published';

  bool get isRejected =>
      status == 'rejected';

  bool get isFailed =>
      status == 'failed';

  bool get canRetryUpload =>
      isUploading ||
      isFailed;

  factory CommunitySubmission.fromJson(
    Map<String, dynamic> json,
  ) {
    final rawTags =
        json['tags'];

    final tags =
        <String>[];

    if (rawTags is List) {
      for (final tag in rawTags) {
        final value =
            tag?.toString().trim() ??
                '';

        if (value.isNotEmpty) {
          tags.add(
            value,
          );
        }
      }
    }

    return CommunitySubmission(
      id:
          json['id']?.toString() ??
              '',
      submittedBy:
          json['submitted_by']
                  ?.toString() ??
              '',
      name:
          json['name']?.toString() ??
              '',
      studio:
          _nullableString(
        json['studio'],
      ),
      category:
          _nullableString(
        json['category'],
      ),
      type:
          _nullableString(
        json['model_type'],
      ),
      scale:
          _nullableString(
        json['scale'],
      ),
      height:
          _nullableString(
        json['height'],
      ),
      description:
          _nullableString(
        json['description'],
      ),
      tags:
          tags,
      status:
          json['status']
                  ?.toString() ??
              'uploading',
      duplicateStatus:
          json['duplicate_status']
                  ?.toString() ??
              'unchecked',
      duplicateOfModelId:
          _nullableString(
        json['duplicate_of_model_id'],
      ),
      archiveFileName:
          _nullableString(
        json['archive_file_name'],
      ),
      archiveSize:
          _readInt(
        json['archive_size'],
      ),
      archiveSha256:
          _nullableString(
        json['archive_sha256'],
      ),
      contentFingerprint:
          _nullableString(
        json['content_fingerprint'],
      ),
      storageKey:
          _nullableString(
        json['storage_key'],
      ),
      uploadError:
          _nullableString(
        json['upload_error'],
      ),
      submittedAt:
          _readDate(
            json['submitted_at'],
          ) ??
          DateTime
              .fromMillisecondsSinceEpoch(
            0,
          ),
      uploadedAt:
          _readDate(
        json['uploaded_at'],
      ),
      reviewedAt:
          _readDate(
        json['reviewed_at'],
      ),
      reviewNote:
          _nullableString(
        json['review_note'],
      ),
    );
  }
}

int _readInt(dynamic value) {
  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(
        value?.toString() ?? '',
      ) ??
      0;
}

DateTime? _readDate(
  dynamic value,
) {
  if (value == null) {
    return null;
  }

  return DateTime.tryParse(
    value.toString(),
  );
}

String? _nullableString(
  dynamic value,
) {
  final text =
      value?.toString().trim() ??
          '';

  return text.isEmpty
      ? null
      : text;
}
