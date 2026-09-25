/// TwoLevelQR SDK.
///
/// Every checkpoint of the QR pipeline is a first-class value:
///
/// ENCODE: text → segments → dataCodewords → +RS ecc → interleave →
///         finalCodewords → place+mask → matrix
/// DECODE: matrix → unmask → rawCodewords (WITH errors) → deinterleave →
///         RS decode → correctedCodewords → segments → text
library two_level_qr;

// ---- Domain: shared primitives ---------------------------------------------
export 'src/domain/error_correction_level.dart';
export 'src/domain/bit_buffer.dart';
export 'src/domain/qr_matrix.dart';
export 'src/domain/mode.dart';
export 'src/domain/segment.dart';
export 'src/domain/hidden_message.dart';

// ---- Domain: pipeline checkpoints (first-class values) ----------------------
export 'src/domain/data_codewords.dart';
export 'src/domain/ecc_codewords.dart';
export 'src/domain/rs_block.dart';
export 'src/domain/final_codewords.dart';
export 'src/domain/raw_codewords.dart';
export 'src/domain/corrected_codewords.dart';
export 'src/domain/mask_pattern.dart';
export 'src/domain/format_info.dart';
export 'src/domain/version_info.dart';
export 'src/domain/version.dart';

// ---- Domain: use-case ports (interfaces) -----------------------------------
export 'src/domain/ports.dart';

// ---- Data: tables & pure services ------------------------------------------
export 'src/data/qr_tables.dart';
export 'src/data/galois_field.dart';
export 'src/data/reed_solomon.dart';
export 'src/data/bit_stream_codec.dart';
export 'src/data/block_interleaver.dart';
export 'src/data/matrix_renderer.dart';
export 'src/data/masking.dart';
export 'src/data/bch.dart';
export 'src/data/format_info_codec.dart';
export 'src/data/version_info_codec.dart';

// ---- Use cases --------------------------------------------------------------
export 'src/usecases/encode_qr.dart';
export 'src/usecases/decode_qr.dart';
export 'src/usecases/encode_hidden_qr.dart';
export 'src/usecases/decode_hidden_qr.dart';

// ---- Public result types ----------------------------------------------------
export 'src/encode_result.dart';
export 'src/decode_result.dart';
export 'src/two_level_qr.dart';

// ---- Hidden-channel services ------------------------------------------------
export 'src/data/keyed_error_scheduler.dart';
