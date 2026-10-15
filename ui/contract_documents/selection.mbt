///|
/// A tenant selected from user access may not have a contract yet. Keep that
/// empty state instead of displaying or previewing another tenant's packet.
fn ContractDocumentsState::selected_packet(
  self : ContractDocumentsState,
) -> @contractdoc.ContractPacket? {
  self.packets
  .iter()
  .find_first(packet => {
    self.selected_packet_id.map_or(true, id => packet.packet_id == id) &&
    self.selected_tenant_ref.map_or(true, tenant => packet.tenant_ref == tenant) &&
    self.order_context.map_or(true, order => packet.order_ref == order)
  })
}
