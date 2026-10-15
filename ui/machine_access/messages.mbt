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
  ContinueToIssuer
  RecoverableDetailsHeading
  LabelAccessisready
  LabelRecoveraccessdetails
  LabelRedeemSSHaccess
  HandoffUnavailableExplanation
  AccessClosingExplanation
  LabelMymachineaccess
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
        "Recover your connection details without issuing a new credential.", "恢复连接信息，不会签发新凭据。",
      )
    RedemptionExplanation =>
      (
        "Retrieve connection details, then get your SSH certificate.", "领取连接信息后，继续获取 SSH 证书。",
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
        "Download your files before expiry. Access then ends and data cleanup begins; files may not be recoverable.",
        "请在到期前下载文件。到期后访问关闭并开始清理数据，文件可能无法恢复。",
      )
    ContinuedAccess =>
      (
        "To extend access, contact your operator before expiry. The extension must be approved and appear in your lease.",
        "需要延期请在到期前联系运维。延期须经批准并更新到租约中才生效。",
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
    NextSteps => ("Connection help", "连接帮助")
    VerifyFingerprint =>
      (
        "Compare the SSH host fingerprint with the one above. If it differs, stop and contact your operator.",
        "请核对 SSH 主机指纹是否与上方一致。不一致时请停止并联系运维。",
      )
    TunnelHelp =>
      (
        "For an app already running on the machine at port 8181: set up your SSH certificate, run this tunnel locally, and keep it open. Then visit http://127.0.0.1:8181. For hosted ComfyUI, use Open workspace.",
        "如机器已在 8181 端口运行应用：配置好 SSH 证书后，在本机运行并保持此隧道，再访问 http://127.0.0.1:8181。托管 ComfyUI 请使用“打开工作空间”。",
      )
    DownloadReminder =>
      (
        "The retrieval timer applies to connection details. Machine access and SSH certificates have separate expiry times.",
        "领取倒计时仅适用于连接信息；机器访问与 SSH 证书各有有效期。",
      )
  }
  @i18n.copy(locale, english, chinese)
}
