///|
test "machine static catalog preserves English and Chinese labels" {
  assert_eq(machine_message(English, LabelExpired), "Expired")
  assert_eq(machine_message(ChineseSimplified, LabelExpired), "已到期")
  assert_eq(
    machine_message(English, LabelScheduledatclosure),
    "Scheduled at closure",
  )
  assert_eq(
    machine_message(ChineseSimplified, LabelScheduledatclosure),
    "将在关闭时执行",
  )
  assert_eq(
    machine_message(English, LabelAccesslockdowninprogress),
    "Access lockdown in progress",
  )
  assert_eq(
    machine_message(ChineseSimplified, LabelAccesslockdowninprogress),
    "正在撤销访问",
  )
  assert_eq(
    machine_message(English, LabelVerifiedcleanupinprogress),
    "Verified cleanup in progress",
  )
  assert_eq(
    machine_message(ChineseSimplified, LabelVerifiedcleanupinprogress),
    "正在验证清理",
  )
  assert_eq(machine_message(English, LabelCleanupverified), "Cleanup verified")
  assert_eq(
    machine_message(ChineseSimplified, LabelCleanupverified),
    "清理已验证",
  )
  assert_eq(
    machine_message(English, LabelCancelledbeforeaccess),
    "Cancelled before access",
  )
  assert_eq(
    machine_message(ChineseSimplified, LabelCancelledbeforeaccess),
    "已在访问前取消",
  )
  assert_eq(
    machine_message(English, SafetyHoldSupport),
    "Safety hold — contact support",
  )
  assert_eq(
    machine_message(ChineseSimplified, SafetyHoldSupport),
    "安全隔离，请联系支持",
  )
  assert_eq(machine_message(English, LabelRequested), "Requested")
  assert_eq(machine_message(ChineseSimplified, LabelRequested), "已申请")
  assert_eq(machine_message(English, LabelReserved), "Reserved")
  assert_eq(machine_message(ChineseSimplified, LabelReserved), "已预留")
  assert_eq(machine_message(English, LabelPreparingaccess), "Preparing access")
  assert_eq(
    machine_message(ChineseSimplified, LabelPreparingaccess),
    "正在准备访问",
  )
  assert_eq(machine_message(English, LabelReady), "Ready")
  assert_eq(machine_message(ChineseSimplified, LabelReady), "已就绪")
  assert_eq(machine_message(English, LabelExpiring), "Expiring")
  assert_eq(machine_message(ChineseSimplified, LabelExpiring), "即将到期")
  assert_eq(machine_message(English, LabelEndingsessions), "Ending sessions")
  assert_eq(
    machine_message(ChineseSimplified, LabelEndingsessions),
    "正在结束会话",
  )
  assert_eq(machine_message(English, LabelRevokingaccess), "Revoking access")
  assert_eq(
    machine_message(ChineseSimplified, LabelRevokingaccess),
    "正在撤销访问",
  )
  assert_eq(machine_message(English, LabelSanitizing), "Sanitizing")
  assert_eq(machine_message(ChineseSimplified, LabelSanitizing), "正在清理")
  assert_eq(machine_message(English, LabelCompleted), "Completed")
  assert_eq(machine_message(ChineseSimplified, LabelCompleted), "已结束")
  assert_eq(machine_message(English, LabelCancelled), "Cancelled")
  assert_eq(machine_message(ChineseSimplified, LabelCancelled), "已取消")
  assert_eq(machine_message(English, LabelSafetyhold), "Safety hold")
  assert_eq(machine_message(ChineseSimplified, LabelSafetyhold), "安全隔离")
  assert_eq(machine_message(English, LabelOnline), "Online")
  assert_eq(machine_message(ChineseSimplified, LabelOnline), "在线")
  assert_eq(machine_message(English, LabelStatusdelayed), "Status delayed")
  assert_eq(
    machine_message(ChineseSimplified, LabelStatusdelayed),
    "状态延迟",
  )
  assert_eq(machine_message(English, LabelStatuspending), "Status pending")
  assert_eq(
    machine_message(ChineseSimplified, LabelStatuspending),
    "状态待确认",
  )
  assert_eq(
    machine_message(English, CredentialPreparation),
    "Credential issuer is preparing access",
  )
  assert_eq(
    machine_message(ChineseSimplified, CredentialPreparation),
    "凭据签发方正在准备访问",
  )
  assert_eq(machine_message(English, LabelReadytoredeem), "Ready to redeem")
  assert_eq(machine_message(ChineseSimplified, LabelReadytoredeem), "可领取")
  assert_eq(
    machine_message(English, RecoverableDetailsStatus),
    "Access details recoverable",
  )
  assert_eq(
    machine_message(ChineseSimplified, RecoverableDetailsStatus),
    "可恢复访问详情",
  )
  assert_eq(machine_message(English, LabelClosed), "Closed")
  assert_eq(machine_message(ChineseSimplified, LabelClosed), "已关闭")
  assert_eq(machine_message(English, LabelEndaccessearly), "End access early")
  assert_eq(
    machine_message(ChineseSimplified, LabelEndaccessearly),
    "提前结束访问",
  )
  assert_eq(
    machine_message(English, ImmediateSessionInterruption),
    "This interrupts sessions immediately",
  )
  assert_eq(
    machine_message(ChineseSimplified, ImmediateSessionInterruption),
    "这将立即中断会话",
  )
  assert_eq(
    machine_message(English, TerminationConsequences),
    "New logins close, credentials are revoked, and the machine stays unavailable until sanitization succeeds.",
  )
  assert_eq(
    machine_message(ChineseSimplified, TerminationConsequences),
    "新登录将被关闭，凭据会被撤销；机器仅在清理成功后才会恢复可用。",
  )
  assert_eq(
    machine_message(English, LabelTypetheexactconfirmation),
    "Type the exact confirmation",
  )
  assert_eq(
    machine_message(ChineseSimplified, LabelTypetheexactconfirmation),
    "请输入完整确认文字",
  )
  assert_eq(machine_message(English, LabelCancel), "Cancel")
  assert_eq(machine_message(ChineseSimplified, LabelCancel), "取消")
  assert_eq(machine_message(English, LabelTerminateaccess), "Terminate access")
  assert_eq(
    machine_message(ChineseSimplified, LabelTerminateaccess),
    "终止访问",
  )
  assert_eq(
    machine_message(English, LabelEXCLUSIVEMACHINE),
    "EXCLUSIVE MACHINE",
  )
  assert_eq(
    machine_message(ChineseSimplified, LabelEXCLUSIVEMACHINE),
    "独占机器",
  )
  assert_eq(machine_message(English, LabelLivestatus), "Live status")
  assert_eq(machine_message(ChineseSimplified, LabelLivestatus), "实时状态")
  assert_eq(machine_message(English, LabelUsername), "Username")
  assert_eq(machine_message(ChineseSimplified, LabelUsername), "用户名")
  assert_eq(machine_message(English, LabelAccessprofile), "Access profile")
  assert_eq(
    machine_message(ChineseSimplified, LabelAccessprofile),
    "访问配置",
  )
  assert_eq(
    machine_message(English, LabelFullmachineSSH),
    "Full machine · SSH",
  )
  assert_eq(
    machine_message(ChineseSimplified, LabelFullmachineSSH),
    "整机访问 · SSH",
  )
  assert_eq(
    machine_message(English, LabelCredentialhandoff),
    "Credential handoff",
  )
  assert_eq(
    machine_message(ChineseSimplified, LabelCredentialhandoff),
    "凭据交接",
  )
  assert_eq(machine_message(English, LabelCleanupsupport), "Cleanup / support")
  assert_eq(
    machine_message(ChineseSimplified, LabelCleanupsupport),
    "清理 / 支持",
  )
  assert_eq(
    machine_message(English, LabelSSHaccessdetails),
    "SSH access details",
  )
  assert_eq(
    machine_message(ChineseSimplified, LabelSSHaccessdetails),
    "SSH 访问详情",
  )
  assert_eq(machine_message(English, LabelHost), "Host")
  assert_eq(machine_message(ChineseSimplified, LabelHost), "主机")
  assert_eq(machine_message(English, LabelPort), "Port")
  assert_eq(machine_message(ChineseSimplified, LabelPort), "端口")
  assert_eq(machine_message(English, LabelHostkey), "Host key")
  assert_eq(machine_message(ChineseSimplified, LabelHostkey), "主机密钥")
  assert_eq(
    machine_message(English, CredentialIssuerExplanation),
    "Continue through the approved credential issuer. Verify the host key before connecting; no password or private key is displayed here.",
  )
  assert_eq(
    machine_message(ChineseSimplified, CredentialIssuerExplanation),
    "请继续前往已批准的凭据签发方。连接前请核对主机密钥；此处不会显示密码或私钥。",
  )
  assert_eq(
    machine_message(English, ContinueToIssuer),
    "Continue to credential issuer",
  )
  assert_eq(
    machine_message(ChineseSimplified, ContinueToIssuer),
    "前往凭据签发方",
  )
  assert_eq(
    machine_message(English, RecoverableDetailsHeading),
    "Access details can be recovered",
  )
  assert_eq(
    machine_message(ChineseSimplified, RecoverableDetailsHeading),
    "可恢复访问详情",
  )
  assert_eq(machine_message(English, LabelAccessisready), "Access is ready")
  assert_eq(
    machine_message(ChineseSimplified, LabelAccessisready),
    "访问已就绪",
  )
  assert_eq(
    machine_message(English, LabelRecoveraccessdetails),
    "Recover access details",
  )
  assert_eq(
    machine_message(ChineseSimplified, LabelRecoveraccessdetails),
    "恢复访问详情",
  )
  assert_eq(machine_message(English, LabelRedeemSSHaccess), "Redeem SSH access")
  assert_eq(
    machine_message(ChineseSimplified, LabelRedeemSSHaccess),
    "领取 SSH 访问凭据",
  )
  assert_eq(
    machine_message(English, HandoffUnavailableExplanation),
    "Credential handoff is unavailable until provisioning completes, and closes automatically at expiry or termination.",
  )
  assert_eq(
    machine_message(ChineseSimplified, HandoffUnavailableExplanation),
    "凭据交接仅在配置完成后可用，并会在到期或终止时自动关闭。",
  )
  assert_eq(
    machine_message(English, AccessClosingExplanation),
    "Access is closing or closed. The machine remains fenced until revocation and sanitization are verified.",
  )
  assert_eq(
    machine_message(ChineseSimplified, AccessClosingExplanation),
    "访问正在关闭或已关闭。机器将在撤销访问并验证清理完成前保持隔离。",
  )
  assert_eq(machine_message(English, LabelMymachineaccess), "My machine access")
  assert_eq(
    machine_message(ChineseSimplified, LabelMymachineaccess),
    "我的机器访问",
  )
  assert_eq(
    machine_message(English, ExclusiveAccessBoundary),
    "Exclusive machine access is separate from your model API quota and hosted WebIDE/ComfyUI workspace. Only an assigned exclusive lease grants SSH access.",
  )
  assert_eq(
    machine_message(ChineseSimplified, ExclusiveAccessBoundary),
    "独占机器访问与模型 API 额度、托管 WebIDE/ComfyUI 工作区相互独立。只有已分配的独占租约才提供 SSH 访问。",
  )
  assert_eq(
    machine_message(English, NoAssignedMachine),
    "No exclusive machine access has been assigned to your identity.",
  )
  assert_eq(
    machine_message(ChineseSimplified, NoAssignedMachine),
    "您的身份尚未获分配独占机器访问权限。",
  )
}

///|
test "every machine message has both nonempty locale values" {
  let messages : Array[MachineMessage] = [
    RecoveryExplanation,
    RedemptionExplanation,
    LabelExpired,
    LabelScheduledatclosure,
    LabelAccesslockdowninprogress,
    LabelVerifiedcleanupinprogress,
    LabelCleanupverified,
    LabelCancelledbeforeaccess,
    SafetyHoldSupport,
    LabelRequested,
    LabelReserved,
    LabelPreparingaccess,
    LabelReady,
    LabelExpiring,
    LabelEndingsessions,
    LabelRevokingaccess,
    LabelSanitizing,
    LabelCompleted,
    LabelCancelled,
    LabelSafetyhold,
    LabelOnline,
    LabelStatusdelayed,
    LabelStatuspending,
    CredentialPreparation,
    LabelReadytoredeem,
    RecoverableDetailsStatus,
    LabelClosed,
    LabelEndaccessearly,
    ImmediateSessionInterruption,
    TerminationConsequences,
    LabelTypetheexactconfirmation,
    LabelCancel,
    LabelTerminateaccess,
    LabelEXCLUSIVEMACHINE,
    LabelLivestatus,
    LabelUsername,
    LabelAccessprofile,
    LabelFullmachineSSH,
    LabelCredentialhandoff,
    LabelCleanupsupport,
    LabelSSHaccessdetails,
    LabelHost,
    LabelPort,
    LabelHostkey,
    CredentialIssuerExplanation,
    ContinueToIssuer,
    RecoverableDetailsHeading,
    LabelAccessisready,
    LabelRecoveraccessdetails,
    LabelRedeemSSHaccess,
    HandoffUnavailableExplanation,
    AccessClosingExplanation,
    LabelMymachineaccess,
    ExclusiveAccessBoundary,
    NoAssignedMachine,
    MachineTime,
    HandoffTime,
    HandoffLimit,
    ExpiryConsequences,
    ContinuedAccess,
    CopyFingerprint,
    CopyHost,
    CopyPort,
    CopyUsername,
    CopyConnection,
    CopyTunnel,
    InvalidConnection,
    NextSteps,
    VerifyFingerprint,
    TunnelHelp,
    DownloadReminder,
  ]
  for message in messages {
    let english = machine_message(English, message)
    let chinese = machine_message(ChineseSimplified, message)
    assert_true(english.trim() != "")
    assert_true(chinese.trim() != "")
    assert_true(english != chinese)
  }
}
