`timescale 1ns/1ps
module net_udp_loop(
    input external_phy_reset, output monitor_clk, output capture_clk, output capture_valid, output [7:0] capture_byte,
    input              clk_200m  ,   
    input              clk_50m  ,  
    input              sys_rst_n , //ϵͳ��λ�źţ��͵�ƽ��Ч 
    //KSZ9031_RGMII�ӿ�   
    output             eth_mdc  ,
    inout              eth_mdio ,     
    input              net_rxc   , //KSZ9031_RGMII��������ʱ��
    input              net_rx_ctl, //KSZ9031RGMII����������Ч�ź�
    input       [3:0]  net_rxd   , //KSZ9031RGMII��������
    output             net_txc   , //KSZ9031RGMII��������ʱ��    
    output             net_tx_ctl, //KSZ9031RGMII���������Ч�ź�
    output      [3:0]  net_txd   , //KSZ9031RGMII�������          
    output             net_rst_n,
    output      [4:0]  debug_led
    );

//parameter define
parameter  IDELAY_VALUE = 8;
parameter  BOARD_MAC = 48'h02_00_00_00_00_01;     
parameter  BOARD_IP  = {8'd192,8'd0,8'd2,8'd1};  
parameter  DES_MAC   = 48'hff_ff_ff_ff_ff_ff;       
parameter  DES_IP    = {8'd192,8'd0,8'd2,8'd2};  

//wire define
            
wire          gmii_rx_clk; //GMII����ʱ��
wire          gmii_rx_en ; //GMII����������Ч�ź�
wire  [7:0]   gmii_rxd   ; //GMII��������
reg [24:0] system_counter;
reg [21:0] receive_counter;
reg saw_frame;
reg saw_sfd;
reg saw_arp_request;

wire arp_rx_done,arp_rx_type;
always @(posedge clk_50m or negedge sys_rst_n) begin
    if (!sys_rst_n)
        system_counter <= 25'd0;
    else
        system_counter <= system_counter + 25'd1;
end

always @(posedge gmii_rx_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        receive_counter <= 22'd0;
        saw_frame <= 1'b0;
        saw_sfd <= 1'b0;
        saw_arp_request <= 1'b0;
    end else begin
        receive_counter <= receive_counter + 22'd1;
        if (gmii_rx_en) begin
            saw_frame <= 1'b1;
            if (gmii_rxd == 8'hd5)
                saw_sfd <= 1'b1;
        end
        if (arp_rx_done && !arp_rx_type)
            saw_arp_request <= 1'b1;
    end
end

assign debug_led[0] = system_counter[24];
assign debug_led[1] = receive_counter[21];
assign debug_led[2] = saw_frame;
assign debug_led[3] = saw_sfd;
assign debug_led[4] = saw_arp_request;
wire          gmii_tx_clk; //GMII����ʱ��
wire          gmii_tx_en ; //GMII��������ʹ���ź�
wire  [7:0]   gmii_txd   ; //GMII��������     

wire          arp_gmii_tx_en; //ARP GMII���������Ч�ź� 
wire  [7:0]   arp_gmii_txd  ; //ARP GMII�������
 //ARP��������ź�
 //ARP�������� 0:����  1:Ӧ��
wire  [47:0]  src_mac       ; //���յ�Ŀ��MAC��ַ
wire  [31:0]  src_ip        ; //���յ�Ŀ��IP��ַ    
wire          arp_tx_en     ; //ARP����ʹ���ź�
wire          arp_tx_type   ; //ARP�������� 0:����  1:Ӧ��
wire  [47:0]  des_mac       ; //���͵�Ŀ��MAC��ַ
wire  [31:0]  des_ip        ; //���͵�Ŀ��IP��ַ   
wire          arp_tx_done   ; //ARP��������ź�

wire          udp_gmii_tx_en; //UDP GMII���������Ч�ź� 
wire  [7:0]   udp_gmii_txd  ; //UDP GMII�������
wire          rec_pkt_done  ; //UDP�������ݽ�������ź�
wire          rec_en        ; //UDP���յ�����ʹ���ź�
wire  [31:0]  rec_data      ; //UDP���յ�����
wire  [15:0]  rec_byte_num  ; //UDP���յ���Ч�ֽ��� ��λ:byte 
wire  [15:0]  tx_byte_num   ; //UDP���͵���Ч�ֽ��� ��λ:byte 
wire          udp_tx_done   ; //UDP��������ź�
wire          tx_req        ; //UDP�����������ź�
wire  [31:0]  tx_data       ; //UDP����������


wire tx_start_en;
///////////////////////main code////////////////////////////////



assign des_mac = src_mac;
assign des_ip = src_ip;



//KSZ9031_phy��λ
assign net_rst_n = external_phy_reset;
assign capture_clk=gmii_rx_clk;
assign capture_valid=gmii_rx_en;
assign capture_byte=gmii_rxd;


gmii_to_rgmii 
    #(
     .IDELAY_VALUE (IDELAY_VALUE)
     )
    u_gmii_to_rgmii(
    .idelay_clk    (clk_200m    ),
    .physical_rx_clk(monitor_clk),

    .gmii_rx_clk   (gmii_rx_clk ),
    .gmii_rx_en    (gmii_rx_en  ),
    .gmii_rxd      (gmii_rxd    ),
    .gmii_tx_clk   (gmii_tx_clk ),
    .gmii_tx_en    (gmii_tx_en  ),
    .gmii_txd      (gmii_txd    ),
    
    .rgmii_rxc     (net_rxc     ),
    .rgmii_rx_ctl  (net_rx_ctl  ),
    .rgmii_rxd     (net_rxd     ),
    .rgmii_txc     (net_txc     ),
    .rgmii_tx_ctl  (net_tx_ctl  ),
    .rgmii_txd     (net_txd     )
    );

//ARPͨ��
arp                                             
   #(
    .BOARD_MAC     (BOARD_MAC),      //��������
    .BOARD_IP      (BOARD_IP ),
    .DES_MAC       (DES_MAC  ),
    .DES_IP        (DES_IP   )
    )
   u_arp(
    .rst_n         (sys_rst_n  ),
                    
    .gmii_rx_clk   (gmii_rx_clk),
    .gmii_rx_en    (gmii_rx_en ),
    .gmii_rxd      (gmii_rxd   ),
    .gmii_tx_clk   (gmii_tx_clk),
    .gmii_tx_en    (arp_gmii_tx_en ),
    .gmii_txd      (arp_gmii_txd),
                    
    .arp_rx_done   (arp_rx_done),
    .arp_rx_type   (arp_rx_type),
    .src_mac       (src_mac    ),
    .src_ip        (src_ip     ),
    .arp_tx_en     (arp_tx_en  ),
    .arp_tx_type   (arp_tx_type),
    .des_mac       (des_mac    ),
    .des_ip        (des_ip     ),
    .tx_done       (arp_tx_done)
    );

//UDPͨ��
udp                                             
   #(
    .BOARD_MAC     (BOARD_MAC),      //��������
    .BOARD_IP      (BOARD_IP ),
    .DES_MAC       (DES_MAC  ),
    .DES_IP        (DES_IP   )
    )
   u_udp(
    .rst_n         (sys_rst_n   ),  
    
    .gmii_rx_clk   (gmii_rx_clk ),           
    .gmii_rx_en    (gmii_rx_en  ),         
    .gmii_rxd      (gmii_rxd    ),                   
    .gmii_tx_clk   (gmii_tx_clk ), 
    .gmii_tx_en    (udp_gmii_tx_en),         
    .gmii_txd      (udp_gmii_txd),  

    .rec_pkt_done  (rec_pkt_done),    
    .rec_en        (rec_en      ),     
    .rec_data      (rec_data    ),         
    .rec_byte_num  (rec_byte_num),      
    .tx_start_en   (tx_start_en ),        
    .tx_data       (tx_data     ),         
    .tx_byte_num   (tx_byte_num ),   
    .tx_done       (udp_tx_done ),        
    .tx_req        (tx_req      )           
    ); 

//FIFO
c3_udp_engine cnn(.clk(clk_50m),.resetn(sys_rst_n),.mac_clk(gmii_rx_clk),
 .rec_en(rec_en),.rec_pkt_done(rec_pkt_done),.rec_data(rec_data),.rec_byte_num(rec_byte_num),
 .tx_req(tx_req),.tx_done(udp_tx_done),.tx_start_en(tx_start_en),.tx_byte_num(tx_byte_num),.tx_data(tx_data));
    

//��̫������ģ��
net_ctrl u_net_ctrl(
    .clk            (gmii_rx_clk),
    .rst_n          (sys_rst_n),

    .arp_rx_done    (arp_rx_done   ),
    .arp_rx_type    (arp_rx_type   ),
    .arp_tx_en      (arp_tx_en     ),
    .arp_tx_type    (arp_tx_type   ),
    .arp_tx_done    (arp_tx_done   ),
    .arp_gmii_tx_en (arp_gmii_tx_en),
    .arp_gmii_txd   (arp_gmii_txd  ),
                     
    .udp_gmii_tx_en (udp_gmii_tx_en),
    .udp_gmii_txd   (udp_gmii_txd  ),
                     
    .gmii_tx_en     (gmii_tx_en    ),
    .gmii_txd       (gmii_txd      )
    );

endmodule

