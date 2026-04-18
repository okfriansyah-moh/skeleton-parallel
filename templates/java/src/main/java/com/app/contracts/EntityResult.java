package com.app.contracts;

/**
 * Processed entity result DTO.
 */
public record EntityResult(
    String entityId,
    String name,
    String status,
    double score,
    String metadata
) {}
