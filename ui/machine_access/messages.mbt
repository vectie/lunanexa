///|
priv enum MachineMessage {
  RecoveryExplanation
  RedemptionExplanation
  LabelExpired
  LabelScheduledatclosure
  LabelAccesslockdowninprogress
  LabelVerifiedcleanupinprogress
  LabelCleanupverified
  LabelCancelledbeforeaccess
  SafetyHoldSupport
  LabelRequested
  LabelReserved
  LabelPreparingaccess
  LabelReady
  LabelExpiring
  LabelEndingsessions
  LabelRevokingaccess
  LabelSanitizing
  LabelCompleted
  LabelCancelled
  LabelSafetyhold
  LabelOnline
  LabelStatusdelayed
  LabelStatuspending
  CredentialPreparation
  LabelReadytoredeem
  RecoverableDetailsStatus
  LabelClosed
  LabelEndaccessearly
  ImmediateSessionInterruption
  TerminationConsequences
  LabelTypetheexactconfirmation
  LabelCancel
  LabelTerminateaccess
  LabelEXCLUSIVEMACHINE
  LabelLivestatus
  LabelUsername
  LabelAccessprofile
  LabelFullmachineSSH
  LabelCredentialhandoff
  LabelCleanupsupport
  LabelSSHaccessdetails
  LabelHost
  LabelPort
  LabelHostkey
  CredentialIssuerExplanation
  ContinueToIssuer
  RecoverableDetailsHeading
  LabelAccessisready
  LabelRecoveraccessdetails
  LabelRedeemSSHaccess
  HandoffUnavailableExplanation
  AccessClosingExplanation
  LabelMymachineaccess
  ExclusiveAccessBoundary
  NoAssignedMachine
  MachineTime
  HandoffTime
  HandoffLimit
  ExpiryConsequences
  ContinuedAccess
  CopyFingerprint
  CopyHost
  CopyPort
  CopyUsername
  CopyConnection
  CopyTunnel
  InvalidConnection
  NextSteps
  VerifyFingerprint
  TunnelHelp
  DownloadReminder
}

///|
fn machine_message(locale : @i18n.Locale, message : MachineMessage) -> String {
  let (english, chinese) = match message {
    RecoveryExplanation =>
      (
        "Recover the same safe connection metadata after a reload; this does not issue another credential.",
        "页面重载后可恢复相同的安全连接信息；不会再次签发凭据。",
      )
    RedemptionExplanation =>
      (
        "Redeem once to reveal safe connection metadata and continue to the short-lived certificate issuer.",
        "仅可领取一次；领取后将显示安全连接信息，并继续前往短期证书签发方。",
      )
    LabelExpired => ("Expired", "已到期")
    LabelScheduledatclosure => ("Scheduled at closure", "将在关闭时执行")
    LabelAccesslockdowninprogress =>
      ("Access lockdown in progress", "正在撤销访问")
    LabelVerifiedcleanupinprogress =>
      ("Verified cleanup in progress", "正在验证清理")
    LabelCleanupverified => ("Cleanup verified", "清理已验证")
    LabelCancelledbeforeaccess =>
      ("Cancelled before access", "已在访问前取消")
    SafetyHoldSupport =>
      ("Safety hold — contact support", "安全隔离，请联系支持")
    LabelRequested => ("Requested", "已申请")
    LabelReserved => ("Reserved", "已预留")
    LabelPreparingaccess => ("Preparing access", "正在准备访问")
    LabelReady => ("Ready", "已就绪")
    LabelExpiring => ("Expiring", "即将到期")
    LabelEndingsessions => ("Ending sessions", "正在结束会话")
    LabelRevokingaccess => ("Revoking access", "正在撤销访问")
    LabelSanitizing => ("Sanitizing", "正在清理")
    LabelCompleted => ("Completed", "已结束")
    LabelCancelled => ("Cancelled", "已取消")
    LabelSafetyhold => ("Safety hold", "安全隔离")
    LabelOnline => ("Online", "在线")
    LabelStatusdelayed => ("Status delayed", "状态延迟")
    LabelStatuspending => ("Status pending", "状态待确认")
    CredentialPreparation =>
      (
        "Credential issuer is preparing access", "凭据签发方正在准备访问",
      )
    LabelReadytoredeem => ("Ready to redeem", "可领取")
    RecoverableDetailsStatus =>
      ("Access details recoverable", "可恢复访问详情")
    LabelClosed => ("Closed", "已关闭")
    LabelEndaccessearly => ("End access early", "提前结束访问")
    ImmediateSessionInterruption =>
      ("This interrupts sessions immediately", "这将立即中断会话")
    TerminationConsequences =>
      (
        "New logins close, credentials are revoked, and the machine stays unavailable until sanitization succeeds.",
        "新登录将被关闭，凭据会被撤销；机器仅在清理成功后才会恢复可用。",
      )
    LabelTypetheexactconfirmation =>
      ("Type the exact confirmation", "请输入完整确认文字")
    LabelCancel => ("Cancel", "取消")
    LabelTerminateaccess => ("Terminate access", "终止访问")
    LabelEXCLUSIVEMACHINE => ("EXCLUSIVE MACHINE", "独占机器")
    LabelLivestatus => ("Live status", "实时状态")
    LabelUsername => ("Username", "用户名")
    LabelAccessprofile => ("Access profile", "访问配置")
    LabelFullmachineSSH => ("Full machine · SSH", "整机访问 · SSH")
    LabelCredentialhandoff => ("Credential handoff", "凭据交接")
    LabelCleanupsupport => ("Cleanup / support", "清理 / 支持")
    LabelSSHaccessdetails => ("SSH access details", "SSH 访问详情")
    LabelHost => ("Host", "主机")
    LabelPort => ("Port", "端口")
    LabelHostkey => ("Host key", "主机密钥")
    CredentialIssuerExplanation =>
      (
        "Continue through the approved credential issuer. Verify the host key before connecting; no password or private key is displayed here.",
        "请继续前往已批准的凭据签发方。连接前请核对主机密钥；此处不会显示密码或私钥。",
      )
    ContinueToIssuer =>
      ("Continue to credential issuer", "前往凭据签发方")
    RecoverableDetailsHeading =>
      ("Access details can be recovered", "可恢复访问详情")
    LabelAccessisready => ("Access is ready", "访问已就绪")
    LabelRecoveraccessdetails =>
      ("Recover access details", "恢复访问详情")
    LabelRedeemSSHaccess => ("Redeem SSH access", "领取 SSH 访问凭据")
    HandoffUnavailableExplanation =>
      (
        "Credential handoff is unavailable until provisioning completes, and closes automatically at expiry or termination.",
        "凭据交接仅在配置完成后可用，并会在到期或终止时自动关闭。",
      )
    AccessClosingExplanation =>
      (
        "Access is closing or closed. The machine remains fenced until revocation and sanitization are verified.",
        "访问正在关闭或已关闭。机器将在撤销访问并验证清理完成前保持隔离。",
      )
    LabelMymachineaccess => ("My machine access", "我的机器访问")
    ExclusiveAccessBoundary =>
      (
        "Exclusive machine access is separate from your model API quota and hosted WebIDE/ComfyUI workspace. Only an assigned exclusive lease grants SSH access.",
        "独占机器访问与模型 API 额度、托管 WebIDE/ComfyUI 工作区相互独立。只有已分配的独占租约才提供 SSH 访问。",
      )
    NoAssignedMachine =>
      (
        "No exclusive machine access has been assigned to your identity.", "您的身份尚未获分配独占机器访问权限。",
      )
    MachineTime => ("Machine access remaining", "机器还能使用多久")
    HandoffTime =>
      (
        "Connection details retrieval remaining", "连接信息还能领取多久",
      )
    HandoffLimit =>
      (
        "Before retrieval, this is the lease-bound upper limit; the credential issuer may close retrieval sooner. It is not the SSH certificate lifetime.",
        "领取前此处显示租约允许的最长领取窗口，凭据签发方可能提前关闭领取。这不是 SSH 证书有效期。",
      )
    ExpiryConsequences =>
      (
        "At machine expiry, access closes and tenant-data cleanup follows. Download results beforehand; do not rely on recovery after closure. Cleanup is verified in stages, not a promise of instant physical disk erasure.",
        "机器到期后将关闭访问并进入租户数据清理。请提前下载成果，不要依赖关闭后的数据恢复。清理分阶段验证，并不代表到期瞬间完成物理磁盘擦除。",
      )
    ContinuedAccess =>
      (
        "Need more time? Contact your operator before expiry to discuss continued access. There is no self-service machine renewal here; access is not extended until separately approved and reflected in the lease.",
        "需要更长时间？请在到期前联系运维确认后续使用安排。此处不提供机器自助延期；只有另行获批并反映到租约后，访问时间才算延长。",
      )
    CopyFingerprint => ("Copy host fingerprint", "复制主机指纹")
    CopyHost => ("Copy host", "复制主机")
    CopyPort => ("Copy port", "复制端口")
    CopyUsername => ("Copy username", "复制用户名")
    CopyConnection => ("Copy SSH command", "复制 SSH 命令")
    CopyTunnel => ("Copy tunnel command", "复制隧道命令")
    InvalidConnection =>
      (
        "Connection metadata is invalid. Contact your operator for corrected access details; do not run a guessed command.",
        "连接信息无效。请联系运维获取正确访问详情，不要运行自行猜测的命令。",
      )
    NextSteps => ("Next steps", "接下来怎么用")
    VerifyFingerprint =>
      (
        "1. On your first SSH connection, compare the displayed SHA256 host fingerprint with the one above before accepting. If it differs, stop and contact your operator; do not disable host-key verification.",
        "1. 首次 SSH 连接时，接受主机前先核对终端显示的 SHA256 指纹是否与上方一致。不一致时请停止并联系运维，不要关闭主机密钥验证。",
      )
    TunnelHelp =>
      (
        "2. If you have started a web application on this exclusive machine at 127.0.0.1:8181, run this in your local terminal, keep it open, then visit http://127.0.0.1:8181 locally. It does not install or start ComfyUI. Hosted ComfyUI uses its Open workspace button instead. Complete the approved SSH certificate setup first.",
        "2. 如果您已在这台独占机器的 127.0.0.1:8181 启动网页应用，请在本机终端运行下方命令并保持终端打开，再用本机浏览器访问 http://127.0.0.1:8181。此命令不会安装或启动 ComfyUI；托管 ComfyUI 请使用“打开工作空间”按钮。请先完成已批准的 SSH 证书配置。",
      )
    DownloadReminder =>
      (
        "3. Download workflows, uploads and generated results before machine access ends. The connection-details timer only limits retrieval/recovery of these details; it does not extend machine access or guarantee certificate validity.",
        "3. 请在机器访问结束前下载工作流、上传文件和生成结果。连接信息倒计时只限制领取或恢复详情，不会延长机器使用时间，也不保证 SSH 证书始终有效。",
      )
  }
  @i18n.copy(locale, english, chinese)
}
