# Supply a reviewed immutable runtime digest containing AWS CLI v2, ClamAV,
# qpdf, unzip/zipgrep and CA roots. Build the native binary before packaging.
ARG RUNTIME_IMAGE
FROM ${RUNTIME_IMAGE}
COPY --chmod=0555 offline-transfer.exe /usr/local/bin/lunanexa-offline-transfer
USER 65532:65532
ENTRYPOINT ["/usr/local/bin/lunanexa-offline-transfer"]
