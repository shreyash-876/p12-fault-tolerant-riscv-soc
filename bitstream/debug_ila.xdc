

create_debug_core u_ila_0 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU_CNT 4 [get_debug_cores u_ila_0]
set_property C_ADV_TRIGGER true [get_debug_cores u_ila_0]
set_property C_DATA_DEPTH 2048 [get_debug_cores u_ila_0]
set_property C_EN_STRG_QUAL true [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
set_property port_width 1 [get_debug_ports u_ila_0/clk]
connect_debug_port u_ila_0/clk [get_nets [list clk]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
set_property port_width 32 [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 [get_nets [list {u_soc/u_mem/scrub_repaired[0]} {u_soc/u_mem/scrub_repaired[1]} {u_soc/u_mem/scrub_repaired[2]} {u_soc/u_mem/scrub_repaired[3]} {u_soc/u_mem/scrub_repaired[4]} {u_soc/u_mem/scrub_repaired[5]} {u_soc/u_mem/scrub_repaired[6]} {u_soc/u_mem/scrub_repaired[7]} {u_soc/u_mem/scrub_repaired[8]} {u_soc/u_mem/scrub_repaired[9]} {u_soc/u_mem/scrub_repaired[10]} {u_soc/u_mem/scrub_repaired[11]} {u_soc/u_mem/scrub_repaired[12]} {u_soc/u_mem/scrub_repaired[13]} {u_soc/u_mem/scrub_repaired[14]} {u_soc/u_mem/scrub_repaired[15]} {u_soc/u_mem/scrub_repaired[16]} {u_soc/u_mem/scrub_repaired[17]} {u_soc/u_mem/scrub_repaired[18]} {u_soc/u_mem/scrub_repaired[19]} {u_soc/u_mem/scrub_repaired[20]} {u_soc/u_mem/scrub_repaired[21]} {u_soc/u_mem/scrub_repaired[22]} {u_soc/u_mem/scrub_repaired[23]} {u_soc/u_mem/scrub_repaired[24]} {u_soc/u_mem/scrub_repaired[25]} {u_soc/u_mem/scrub_repaired[26]} {u_soc/u_mem/scrub_repaired[27]} {u_soc/u_mem/scrub_repaired[28]} {u_soc/u_mem/scrub_repaired[29]} {u_soc/u_mem/scrub_repaired[30]} {u_soc/u_mem/scrub_repaired[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
set_property port_width 32 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets [list {u_soc/u_mem/scrub_sweeps[0]} {u_soc/u_mem/scrub_sweeps[1]} {u_soc/u_mem/scrub_sweeps[2]} {u_soc/u_mem/scrub_sweeps[3]} {u_soc/u_mem/scrub_sweeps[4]} {u_soc/u_mem/scrub_sweeps[5]} {u_soc/u_mem/scrub_sweeps[6]} {u_soc/u_mem/scrub_sweeps[7]} {u_soc/u_mem/scrub_sweeps[8]} {u_soc/u_mem/scrub_sweeps[9]} {u_soc/u_mem/scrub_sweeps[10]} {u_soc/u_mem/scrub_sweeps[11]} {u_soc/u_mem/scrub_sweeps[12]} {u_soc/u_mem/scrub_sweeps[13]} {u_soc/u_mem/scrub_sweeps[14]} {u_soc/u_mem/scrub_sweeps[15]} {u_soc/u_mem/scrub_sweeps[16]} {u_soc/u_mem/scrub_sweeps[17]} {u_soc/u_mem/scrub_sweeps[18]} {u_soc/u_mem/scrub_sweeps[19]} {u_soc/u_mem/scrub_sweeps[20]} {u_soc/u_mem/scrub_sweeps[21]} {u_soc/u_mem/scrub_sweeps[22]} {u_soc/u_mem/scrub_sweeps[23]} {u_soc/u_mem/scrub_sweeps[24]} {u_soc/u_mem/scrub_sweeps[25]} {u_soc/u_mem/scrub_sweeps[26]} {u_soc/u_mem/scrub_sweeps[27]} {u_soc/u_mem/scrub_sweeps[28]} {u_soc/u_mem/scrub_sweeps[29]} {u_soc/u_mem/scrub_sweeps[30]} {u_soc/u_mem/scrub_sweeps[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe2]
set_property port_width 32 [get_debug_ports u_ila_0/probe2]
connect_debug_port u_ila_0/probe2 [get_nets [list {u_soc/u_mem/scrub_ue[0]} {u_soc/u_mem/scrub_ue[1]} {u_soc/u_mem/scrub_ue[2]} {u_soc/u_mem/scrub_ue[3]} {u_soc/u_mem/scrub_ue[4]} {u_soc/u_mem/scrub_ue[5]} {u_soc/u_mem/scrub_ue[6]} {u_soc/u_mem/scrub_ue[7]} {u_soc/u_mem/scrub_ue[8]} {u_soc/u_mem/scrub_ue[9]} {u_soc/u_mem/scrub_ue[10]} {u_soc/u_mem/scrub_ue[11]} {u_soc/u_mem/scrub_ue[12]} {u_soc/u_mem/scrub_ue[13]} {u_soc/u_mem/scrub_ue[14]} {u_soc/u_mem/scrub_ue[15]} {u_soc/u_mem/scrub_ue[16]} {u_soc/u_mem/scrub_ue[17]} {u_soc/u_mem/scrub_ue[18]} {u_soc/u_mem/scrub_ue[19]} {u_soc/u_mem/scrub_ue[20]} {u_soc/u_mem/scrub_ue[21]} {u_soc/u_mem/scrub_ue[22]} {u_soc/u_mem/scrub_ue[23]} {u_soc/u_mem/scrub_ue[24]} {u_soc/u_mem/scrub_ue[25]} {u_soc/u_mem/scrub_ue[26]} {u_soc/u_mem/scrub_ue[27]} {u_soc/u_mem/scrub_ue[28]} {u_soc/u_mem/scrub_ue[29]} {u_soc/u_mem/scrub_ue[30]} {u_soc/u_mem/scrub_ue[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe3]
set_property port_width 32 [get_debug_ports u_ila_0/probe3]
connect_debug_port u_ila_0/probe3 [get_nets [list {u_soc/u_core/if_id_pc[0]} {u_soc/u_core/if_id_pc[1]} {u_soc/u_core/if_id_pc[2]} {u_soc/u_core/if_id_pc[3]} {u_soc/u_core/if_id_pc[4]} {u_soc/u_core/if_id_pc[5]} {u_soc/u_core/if_id_pc[6]} {u_soc/u_core/if_id_pc[7]} {u_soc/u_core/if_id_pc[8]} {u_soc/u_core/if_id_pc[9]} {u_soc/u_core/if_id_pc[10]} {u_soc/u_core/if_id_pc[11]} {u_soc/u_core/if_id_pc[12]} {u_soc/u_core/if_id_pc[13]} {u_soc/u_core/if_id_pc[14]} {u_soc/u_core/if_id_pc[15]} {u_soc/u_core/if_id_pc[16]} {u_soc/u_core/if_id_pc[17]} {u_soc/u_core/if_id_pc[18]} {u_soc/u_core/if_id_pc[19]} {u_soc/u_core/if_id_pc[20]} {u_soc/u_core/if_id_pc[21]} {u_soc/u_core/if_id_pc[22]} {u_soc/u_core/if_id_pc[23]} {u_soc/u_core/if_id_pc[24]} {u_soc/u_core/if_id_pc[25]} {u_soc/u_core/if_id_pc[26]} {u_soc/u_core/if_id_pc[27]} {u_soc/u_core/if_id_pc[28]} {u_soc/u_core/if_id_pc[29]} {u_soc/u_core/if_id_pc[30]} {u_soc/u_core/if_id_pc[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe4]
set_property port_width 32 [get_debug_ports u_ila_0/probe4]
connect_debug_port u_ila_0/probe4 [get_nets [list {u_soc/u_mem/u_regs/ce_count[0]} {u_soc/u_mem/u_regs/ce_count[1]} {u_soc/u_mem/u_regs/ce_count[2]} {u_soc/u_mem/u_regs/ce_count[3]} {u_soc/u_mem/u_regs/ce_count[4]} {u_soc/u_mem/u_regs/ce_count[5]} {u_soc/u_mem/u_regs/ce_count[6]} {u_soc/u_mem/u_regs/ce_count[7]} {u_soc/u_mem/u_regs/ce_count[8]} {u_soc/u_mem/u_regs/ce_count[9]} {u_soc/u_mem/u_regs/ce_count[10]} {u_soc/u_mem/u_regs/ce_count[11]} {u_soc/u_mem/u_regs/ce_count[12]} {u_soc/u_mem/u_regs/ce_count[13]} {u_soc/u_mem/u_regs/ce_count[14]} {u_soc/u_mem/u_regs/ce_count[15]} {u_soc/u_mem/u_regs/ce_count[16]} {u_soc/u_mem/u_regs/ce_count[17]} {u_soc/u_mem/u_regs/ce_count[18]} {u_soc/u_mem/u_regs/ce_count[19]} {u_soc/u_mem/u_regs/ce_count[20]} {u_soc/u_mem/u_regs/ce_count[21]} {u_soc/u_mem/u_regs/ce_count[22]} {u_soc/u_mem/u_regs/ce_count[23]} {u_soc/u_mem/u_regs/ce_count[24]} {u_soc/u_mem/u_regs/ce_count[25]} {u_soc/u_mem/u_regs/ce_count[26]} {u_soc/u_mem/u_regs/ce_count[27]} {u_soc/u_mem/u_regs/ce_count[28]} {u_soc/u_mem/u_regs/ce_count[29]} {u_soc/u_mem/u_regs/ce_count[30]} {u_soc/u_mem/u_regs/ce_count[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe5]
set_property port_width 32 [get_debug_ports u_ila_0/probe5]
connect_debug_port u_ila_0/probe5 [get_nets [list {u_soc/u_mem/u_regs/ue_count[0]} {u_soc/u_mem/u_regs/ue_count[1]} {u_soc/u_mem/u_regs/ue_count[2]} {u_soc/u_mem/u_regs/ue_count[3]} {u_soc/u_mem/u_regs/ue_count[4]} {u_soc/u_mem/u_regs/ue_count[5]} {u_soc/u_mem/u_regs/ue_count[6]} {u_soc/u_mem/u_regs/ue_count[7]} {u_soc/u_mem/u_regs/ue_count[8]} {u_soc/u_mem/u_regs/ue_count[9]} {u_soc/u_mem/u_regs/ue_count[10]} {u_soc/u_mem/u_regs/ue_count[11]} {u_soc/u_mem/u_regs/ue_count[12]} {u_soc/u_mem/u_regs/ue_count[13]} {u_soc/u_mem/u_regs/ue_count[14]} {u_soc/u_mem/u_regs/ue_count[15]} {u_soc/u_mem/u_regs/ue_count[16]} {u_soc/u_mem/u_regs/ue_count[17]} {u_soc/u_mem/u_regs/ue_count[18]} {u_soc/u_mem/u_regs/ue_count[19]} {u_soc/u_mem/u_regs/ue_count[20]} {u_soc/u_mem/u_regs/ue_count[21]} {u_soc/u_mem/u_regs/ue_count[22]} {u_soc/u_mem/u_regs/ue_count[23]} {u_soc/u_mem/u_regs/ue_count[24]} {u_soc/u_mem/u_regs/ue_count[25]} {u_soc/u_mem/u_regs/ue_count[26]} {u_soc/u_mem/u_regs/ue_count[27]} {u_soc/u_mem/u_regs/ue_count[28]} {u_soc/u_mem/u_regs/ue_count[29]} {u_soc/u_mem/u_regs/ue_count[30]} {u_soc/u_mem/u_regs/ue_count[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe6]
set_property port_width 32 [get_debug_ports u_ila_0/probe6]
connect_debug_port u_ila_0/probe6 [get_nets [list {u_soc/u_mem/ev_addr[0]} {u_soc/u_mem/ev_addr[1]} {u_soc/u_mem/ev_addr[2]} {u_soc/u_mem/ev_addr[3]} {u_soc/u_mem/ev_addr[4]} {u_soc/u_mem/ev_addr[5]} {u_soc/u_mem/ev_addr[6]} {u_soc/u_mem/ev_addr[7]} {u_soc/u_mem/ev_addr[8]} {u_soc/u_mem/ev_addr[9]} {u_soc/u_mem/ev_addr[10]} {u_soc/u_mem/ev_addr[11]} {u_soc/u_mem/ev_addr[12]} {u_soc/u_mem/ev_addr[13]} {u_soc/u_mem/ev_addr[14]} {u_soc/u_mem/ev_addr[15]} {u_soc/u_mem/ev_addr[16]} {u_soc/u_mem/ev_addr[17]} {u_soc/u_mem/ev_addr[18]} {u_soc/u_mem/ev_addr[19]} {u_soc/u_mem/ev_addr[20]} {u_soc/u_mem/ev_addr[21]} {u_soc/u_mem/ev_addr[22]} {u_soc/u_mem/ev_addr[23]} {u_soc/u_mem/ev_addr[24]} {u_soc/u_mem/ev_addr[25]} {u_soc/u_mem/ev_addr[26]} {u_soc/u_mem/ev_addr[27]} {u_soc/u_mem/ev_addr[28]} {u_soc/u_mem/ev_addr[29]} {u_soc/u_mem/ev_addr[30]} {u_soc/u_mem/ev_addr[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe7]
set_property port_width 6 [get_debug_ports u_ila_0/probe7]
connect_debug_port u_ila_0/probe7 [get_nets [list {u_soc/u_mem/ev_pos[0]} {u_soc/u_mem/ev_pos[1]} {u_soc/u_mem/ev_pos[2]} {u_soc/u_mem/ev_pos[3]} {u_soc/u_mem/ev_pos[4]} {u_soc/u_mem/ev_pos[5]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe8]
set_property port_width 32 [get_debug_ports u_ila_0/probe8]
connect_debug_port u_ila_0/probe8 [get_nets [list {u_soc/u_mem/c_req_addr[0]} {u_soc/u_mem/c_req_addr[1]} {u_soc/u_mem/c_req_addr[2]} {u_soc/u_mem/c_req_addr[3]} {u_soc/u_mem/c_req_addr[4]} {u_soc/u_mem/c_req_addr[5]} {u_soc/u_mem/c_req_addr[6]} {u_soc/u_mem/c_req_addr[7]} {u_soc/u_mem/c_req_addr[8]} {u_soc/u_mem/c_req_addr[9]} {u_soc/u_mem/c_req_addr[10]} {u_soc/u_mem/c_req_addr[11]} {u_soc/u_mem/c_req_addr[12]} {u_soc/u_mem/c_req_addr[13]} {u_soc/u_mem/c_req_addr[14]} {u_soc/u_mem/c_req_addr[15]} {u_soc/u_mem/c_req_addr[16]} {u_soc/u_mem/c_req_addr[17]} {u_soc/u_mem/c_req_addr[18]} {u_soc/u_mem/c_req_addr[19]} {u_soc/u_mem/c_req_addr[20]} {u_soc/u_mem/c_req_addr[21]} {u_soc/u_mem/c_req_addr[22]} {u_soc/u_mem/c_req_addr[23]} {u_soc/u_mem/c_req_addr[24]} {u_soc/u_mem/c_req_addr[25]} {u_soc/u_mem/c_req_addr[26]} {u_soc/u_mem/c_req_addr[27]} {u_soc/u_mem/c_req_addr[28]} {u_soc/u_mem/c_req_addr[29]} {u_soc/u_mem/c_req_addr[30]} {u_soc/u_mem/c_req_addr[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe9]
set_property port_width 2 [get_debug_ports u_ila_0/probe9]
connect_debug_port u_ila_0/probe9 [get_nets [list {u_soc/u_mem/c_req_op[0]} {u_soc/u_mem/c_req_op[1]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe10]
set_property port_width 32 [get_debug_ports u_ila_0/probe10]
connect_debug_port u_ila_0/probe10 [get_nets [list {u_soc/u_mem/m_req_addr[0]} {u_soc/u_mem/m_req_addr[1]} {u_soc/u_mem/m_req_addr[2]} {u_soc/u_mem/m_req_addr[3]} {u_soc/u_mem/m_req_addr[4]} {u_soc/u_mem/m_req_addr[5]} {u_soc/u_mem/m_req_addr[6]} {u_soc/u_mem/m_req_addr[7]} {u_soc/u_mem/m_req_addr[8]} {u_soc/u_mem/m_req_addr[9]} {u_soc/u_mem/m_req_addr[10]} {u_soc/u_mem/m_req_addr[11]} {u_soc/u_mem/m_req_addr[12]} {u_soc/u_mem/m_req_addr[13]} {u_soc/u_mem/m_req_addr[14]} {u_soc/u_mem/m_req_addr[15]} {u_soc/u_mem/m_req_addr[16]} {u_soc/u_mem/m_req_addr[17]} {u_soc/u_mem/m_req_addr[18]} {u_soc/u_mem/m_req_addr[19]} {u_soc/u_mem/m_req_addr[20]} {u_soc/u_mem/m_req_addr[21]} {u_soc/u_mem/m_req_addr[22]} {u_soc/u_mem/m_req_addr[23]} {u_soc/u_mem/m_req_addr[24]} {u_soc/u_mem/m_req_addr[25]} {u_soc/u_mem/m_req_addr[26]} {u_soc/u_mem/m_req_addr[27]} {u_soc/u_mem/m_req_addr[28]} {u_soc/u_mem/m_req_addr[29]} {u_soc/u_mem/m_req_addr[30]} {u_soc/u_mem/m_req_addr[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe11]
set_property port_width 2 [get_debug_ports u_ila_0/probe11]
connect_debug_port u_ila_0/probe11 [get_nets [list {u_soc/u_mem/m_req_op[0]} {u_soc/u_mem/m_req_op[1]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe12]
set_property port_width 4 [get_debug_ports u_ila_0/probe12]
connect_debug_port u_ila_0/probe12 [get_nets [list {u_soc/u_mem/m_req_wstrb[0]} {u_soc/u_mem/m_req_wstrb[1]} {u_soc/u_mem/m_req_wstrb[2]} {u_soc/u_mem/m_req_wstrb[3]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe13]
set_property port_width 32 [get_debug_ports u_ila_0/probe13]
connect_debug_port u_ila_0/probe13 [get_nets [list {u_soc/u_mem/ij_count[0]} {u_soc/u_mem/ij_count[1]} {u_soc/u_mem/ij_count[2]} {u_soc/u_mem/ij_count[3]} {u_soc/u_mem/ij_count[4]} {u_soc/u_mem/ij_count[5]} {u_soc/u_mem/ij_count[6]} {u_soc/u_mem/ij_count[7]} {u_soc/u_mem/ij_count[8]} {u_soc/u_mem/ij_count[9]} {u_soc/u_mem/ij_count[10]} {u_soc/u_mem/ij_count[11]} {u_soc/u_mem/ij_count[12]} {u_soc/u_mem/ij_count[13]} {u_soc/u_mem/ij_count[14]} {u_soc/u_mem/ij_count[15]} {u_soc/u_mem/ij_count[16]} {u_soc/u_mem/ij_count[17]} {u_soc/u_mem/ij_count[18]} {u_soc/u_mem/ij_count[19]} {u_soc/u_mem/ij_count[20]} {u_soc/u_mem/ij_count[21]} {u_soc/u_mem/ij_count[22]} {u_soc/u_mem/ij_count[23]} {u_soc/u_mem/ij_count[24]} {u_soc/u_mem/ij_count[25]} {u_soc/u_mem/ij_count[26]} {u_soc/u_mem/ij_count[27]} {u_soc/u_mem/ij_count[28]} {u_soc/u_mem/ij_count[29]} {u_soc/u_mem/ij_count[30]} {u_soc/u_mem/ij_count[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe14]
set_property port_width 7 [get_debug_ports u_ila_0/probe14]
connect_debug_port u_ila_0/probe14 [get_nets [list {u_soc/u_mem/ev_syn[0]} {u_soc/u_mem/ev_syn[1]} {u_soc/u_mem/ev_syn[2]} {u_soc/u_mem/ev_syn[3]} {u_soc/u_mem/ev_syn[4]} {u_soc/u_mem/ev_syn[5]} {u_soc/u_mem/ev_syn[6]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe15]
set_property port_width 1 [get_debug_ports u_ila_0/probe15]
connect_debug_port u_ila_0/probe15 [get_nets [list u_soc/u_mem/c_req_ready]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe16]
set_property port_width 1 [get_debug_ports u_ila_0/probe16]
connect_debug_port u_ila_0/probe16 [get_nets [list u_soc/u_mem/c_req_valid]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe17]
set_property port_width 1 [get_debug_ports u_ila_0/probe17]
connect_debug_port u_ila_0/probe17 [get_nets [list u_soc/u_mem/ev_ce]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe18]
set_property port_width 1 [get_debug_ports u_ila_0/probe18]
connect_debug_port u_ila_0/probe18 [get_nets [list u_soc/u_mem/ev_scrub]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe19]
set_property port_width 1 [get_debug_ports u_ila_0/probe19]
connect_debug_port u_ila_0/probe19 [get_nets [list u_soc/u_mem/ev_ue]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe20]
set_property port_width 1 [get_debug_ports u_ila_0/probe20]
connect_debug_port u_ila_0/probe20 [get_nets [list u_soc/u_mem/ev_valid]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe21]
set_property port_width 1 [get_debug_ports u_ila_0/probe21]
connect_debug_port u_ila_0/probe21 [get_nets [list u_soc/u_mem/m_req_ready]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe22]
set_property port_width 1 [get_debug_ports u_ila_0/probe22]
connect_debug_port u_ila_0/probe22 [get_nets [list u_soc/u_mem/m_req_valid]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe23]
set_property port_width 1 [get_debug_ports u_ila_0/probe23]
connect_debug_port u_ila_0/probe23 [get_nets [list u_soc/u_mem/m_rsp_err]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe24]
set_property port_width 1 [get_debug_ports u_ila_0/probe24]
connect_debug_port u_ila_0/probe24 [get_nets [list u_soc/u_mem/m_rsp_valid]]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk]
