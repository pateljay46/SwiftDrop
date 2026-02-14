/// Transport layer for SwiftDrop.
///
/// Manages TCP connections for chunked file streaming, implements the
/// wire protocol, and handles ACK/NACK/retry logic.
library;

export 'file_chunker.dart';
export 'protocol_codec.dart';
export 'protocol_messages.dart';
export 'transport_connection.dart';
export 'transport_service.dart';
