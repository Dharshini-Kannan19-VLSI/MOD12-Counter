///////////////////RTL///////////////////////////
/*module counter_MOD12(input bit clk, rst, load, mode,
                     input bit [3:0] data_in,
                     output logic [3:0] data_out);

  always @(posedge clk) begin
    if (rst)
      data_out <= 4'd0;
    else if (load)
      data_out <= data_in;
    else if (mode)
      data_out <= (data_out == 4'd11) ? 4'd0 : data_out + 1;
    else
      data_out <= (data_out == 4'd0) ? 4'd11 : data_out - 1;
  end

endmodule*/
module counter_MOD12(
  input bit clk, rst, load, mode,
  input bit [3:0] data_in,
  output logic [3:0] data_out
);

  always @(posedge clk) begin
    if (rst)
      data_out <= 4'd0;
    else if (load)
      data_out <= data_in;
    else if (mode) begin
      if (data_out == 4'd11)
        data_out <= 4'd0;
      else
        data_out <= data_out + 1'b1;
    end else begin
      if (data_out == 4'd0)
        data_out <= 4'd11;
      else
        data_out <= data_out - 1'b1;  
    end
  end

endmodule    


///////////////////////2. Interface///////////////////////////

interface counter_if(input bit clk);

  logic rst;
  logic load;
  logic mode;
  logic [3:0] data_in;
  logic [3:0] data_out;
  
  // Clocking blocks for write driver
  clocking wr_drv_cb @(posedge clk);
    default input #1 output #1;
    output rst, mode, data_in, load;
  endclocking : wr_drv_cb
//cb for wm
  clocking wr_mon_cb @(posedge clk);
    default input #1 output #1;
    input rst, mode, data_in, load;
  endclocking:wr_mon_cb
  //cb for r m
  clocking rd_mon_cb @(posedge clk);
    default input #1 output #1;
    input data_out;
  endclocking:rd_mon_cb

  // Modports
  modport WR_DRV(clocking wr_drv_cb);
  modport WR_MON(clocking wr_mon_cb);
  modport RD_MON(clocking rd_mon_cb);

endinterface:counter_if



/////SVTB//////////////////
/*1.Transaction
2.Generator
3.WRITE driver
4.WRITE Monitor
5.READ driver
6.READ Monitor
7.REFERENCE Model
8.SCORE BOARD
9.Environment
10.TOP module*/



///////////////////////1. Transaction////////////////////

class counter_trans;
  rand bit [3:0] data_in;
  rand bit rst, load, mode;
  logic [3:0] data_out;

 /* constraint c1 { rst dist {0:=10, 1:=1}; }
  constraint c2 { load dist {0:=4, 1:=1}; }
  constraint c3 { mode dist {0:=10, 1:=10}; }
  constraint c4 { data_in inside {[0:11]}; } 
*/
 constraint c_rst      { rst  dist {0:=2, 1:=8}; }            // Mostly asserted
  constraint c_load     { load dist {0:=2, 1:=2}; }            // Load 
  constraint c_mode     { mode dist {0:=1, 1:=1}; }            // Up and Down equal weight
  constraint c_data_in  { data_in inside {[0:11]}; }           // Valid MOD12 range
  
  
  static int tr_id;
  int no_of_transactions = 200;

  function void display(string s);
    $display("----------");
 $display("\n input string message :%s",s);
    $display($time, " %s -> rst=%b load=%b mode=%b data_in=%0d data_out=%0d",
             s, rst, load, mode, data_in, data_out);
    $display("----------");
  endfunction

  function void post_randomize();
    tr_id++;
  endfunction
endclass


/////////////////////2. Generator

class counter_gen;
  counter_trans gen_trans, data2send;
  mailbox #(counter_trans) gen2wr;  //mb handle

  function new(mailbox #(counter_trans) gen2wr);//oc
    this.gen2wr = gen2wr;
    gen_trans = new();
  endfunction

  virtual task start();
    fork
   begin
       for (int i = 0; i < gen_trans.no_of_transactions; i++) begin
        assert(gen_trans.randomize());
        data2send = new gen_trans;//shallow copy
  //data2send =  gen_trans;

        gen2wr.put(data2send);
  
      end
   end
    join_none
  endtask
endclass


//////////////// 3. Write Driver
class counter_write_drv;

  virtual counter_if.WR_DRV wr_drv_if;//virtual local if handle.
  counter_trans data2duv;
  mailbox #(counter_trans) gen2wr;
///overriding
  function new(virtual counter_if.WR_DRV wr_drv_if,
               mailbox #(counter_trans) gen2wr);
    this.wr_drv_if = wr_drv_if;
    this.gen2wr = gen2wr;
  endfunction

  virtual task drive();
    @(wr_drv_if.wr_drv_cb); 
 
 begin
  wr_drv_if.wr_drv_cb.rst     <= data2duv.rst;//desti to source
    wr_drv_if.wr_drv_cb.load    <= data2duv.load;
    wr_drv_if.wr_drv_cb.mode    <= data2duv.mode;
    wr_drv_if.wr_drv_cb.data_in <= data2duv.data_in;
 end
  endtask

  virtual task start();
    fork
   begin
         forever
        begin
               gen2wr.get(data2duv);
               drive();
              end
   end
    join_none
  endtask
endclass

/////////////////4. Write Monitor

class counter_write_mon;
  virtual counter_if.WR_MON wr_mon_if;//virtual handle
  counter_trans data2rm, data2rm2;//rm to refe model
  mailbox #(counter_trans) wr2rm; ///


//oc
  function new(virtual counter_if.WR_MON wr_mon_if,
               mailbox #(counter_trans) wr2rm);
    this.wr_mon_if = wr_mon_if;
    this.wr2rm = wr2rm;
    data2rm = new();
  endfunction

  task monitor();
    //@(wr_mon_if.wr_mon_cb);
  @(wr_mon_if.wr_mon_cb);  // sync to clock

      wait(wr_mon_if.wr_mon_cb.load == 1); // wait until load is asserted

      @(wr_mon_if.wr_mon_cb); // wait one more clock for DUT to react
   
 begin
    data2rm.rst     = wr_mon_if.wr_mon_cb.rst;
    data2rm.load    = wr_mon_if.wr_mon_cb.load;
    data2rm.mode    = wr_mon_if.wr_mon_cb.mode;
    data2rm.data_in = wr_mon_if.wr_mon_cb.data_in;
 end
  endtask

  virtual task start();
    fork
 begin
      forever begin
        monitor();//samples datas from if
       data2rm2 = new data2rm;//shallo copy is done here
    // data2rm2 = data2rm;

        wr2rm.put(data2rm2);
      end
   end
    join_none
  endtask
endclass


//////////////// 5. Read Monitor

class counter_read_mon;
  virtual counter_if.RD_MON rd_mon_if;
  counter_trans data2rm, data2sb;
  mailbox #(counter_trans) rmon2sb;

  function new(virtual counter_if.RD_MON rd_mon_if,
               mailbox #(counter_trans) rmon2sb);
    this.rd_mon_if = rd_mon_if;
    this.rmon2sb = rmon2sb;
    data2rm = new();//restriction due multiple objects created in svtb
  endfunction

  task monitor();
    //@(rd_mon_if.rd_mon_cb);
  @(rd_mon_if.rd_mon_cb); // align to clock

      // Wait until we expect data_out to be valid (optional wait condition)
      // If read signal exists:
      // wait(rd_mon_if.rd_mon_cb.read == 1);

      @(rd_mon_if.rd_mon_cb); // one more cycle to stabilize
   
 begin
    data2rm.data_out = rd_mon_if.rd_mon_cb.data_out;
    data2rm.display("\nRead Monitor Data");
 end
  endtask

  virtual task start();
    fork
      forever begin
        monitor();
        data2sb = new data2rm;
  //data2sb = data2rm;
  

        rmon2sb.put(data2sb);//received by sb
  
      end
    join_none
  endtask
endclass


/////////////////////6. Reference Model

class counter_ref_mod;
  counter_trans mon_data;
  mailbox #(counter_trans) wr2rm, rm2sb;
  bit [3:0] model_data = 0; // internal reference model state

  function new(mailbox #(counter_trans) wr2rm,
               mailbox #(counter_trans) rm2sb);
    this.wr2rm = wr2rm;
    this.rm2sb = rm2sb;
  endfunction

  /*task counter(counter_trans mon_data);
    if (mon_data.rst)
      mon_data.data_out = 4'd0;
    else if (mon_data.load)
      mon_data.data_out = mon_data.data_in;
    else if (mon_data.mode)
      mon_data.data_out = (mon_data.data_out == 4'd11) ? 4'd0 : mon_data.data_out + 1;
    else
      mon_data.data_out = (mon_data.data_out == 4'd0) ? 4'd11 : mon_data.data_out - 1;
  endtask*/
 /*task counter(counter_trans mon_data);
  begin
  if (mon_data.rst)begin
    //mon_data.data_out = 4'd0;   
  model_data = 4'd0; //update model state
 end
  else if (mon_data.load)begin 
   // mon_data.data_out = mon_data.data_in;
  model_data = mon_data.data_in; // assign load value
 end
  else if (mon_data.mode) 
  begin
    if (mon_data.data_out == 4'd11) 
      mon_data.data_out = 4'd0;
    else
      mon_data.data_out = mon_data.data_out + 1;
  end else begin
    if (mon_data.data_out == 4'd0)
      mon_data.data_out = 4'd11;
    else
      mon_data.data_out = mon_data.data_out - 1;
   
  end
  $display("[REF MODEL] rst=%0b load=%0b mode=%0b data_in=%0d -> model_data=%0d",
          mon_data.rst, mon_data.load, mon_data.mode, mon_data.data_in, model_data);
mon_data.data_out = model_data; // assign model output
  end
endtask*/
task counter(counter_trans mon_data);
  begin
    if (mon_data.rst) begin
      model_data = 4'd0;
    end
    else if (mon_data.load) begin
      model_data = mon_data.data_in;
    end
    else if (mon_data.mode) begin
      if (model_data == 4'd11)
        model_data = 4'd0;
      else
        model_data = model_data + 1;
    end else begin
      if (model_data == 4'd0)
        model_data = 4'd11;
      else
        model_data = model_data - 1;
    end

    mon_data.data_out = model_data; // assign model output after update

    $display("[REF MODEL] rst=%0b load=%0b mode=%0b data_in=%0d => model_data=%0d",
             mon_data.rst, mon_data.load, mon_data.mode, mon_data.data_in, model_data);
  end
endtask





  virtual task start();
    fork
      begin
       fork
        begin
                        forever
                 begin
         
                                   wr2rm.get(mon_data);//wm
                                   counter(mon_data);//
                                   rm2sb.put(mon_data);//received by sb
         


                                   mon_data.display("Reference Model");
          
        end
                  end
             join
    end
 join_none
  endtask
endclass




////////////////////7. Scoreboard

class counter_sb;
  event DONE;
  int data_verified = 0, data_match = 0, data_mismatch = 0;
  counter_trans rm_data, rcvd_data, cov_data;
  mailbox #(counter_trans) rm2sb, rd2sb;

  covergroup coverage;
    RST: coverpoint cov_data.rst;
    LOAD: coverpoint cov_data.load;
    MODE: coverpoint cov_data.mode;
    DATA_IN: coverpoint cov_data.data_in { bins a = {[1:10]}; }
    CR: cross RST, LOAD, MODE, DATA_IN;
  endgroup

  function new(mailbox #(counter_trans) rm2sb,
               mailbox #(counter_trans) rd2sb);
    this.rm2sb = rm2sb;
    this.rd2sb = rd2sb;
    coverage = new();
  endfunction

  virtual task check(counter_trans rddata);
  
    if (rm_data.data_out == rddata.data_out) begin
      $display("\nData Verified");
      data_match++;
    end
    else begin
     /* $display("Data Mismatch");
      data_mismatch++;*/
   // 
    $display("\n[ data MISMATCH] @%0t", $time);
    $display("  REF MODEL => data_out = %0d", rm_data.data_out);
    $display("  DUT       => data_out = %0d", rddata.data_out);
    $display("  Inputs    => rst = %0b | load = %0b | mode = %0b | data_in = %0d",
             rm_data.rst, rm_data.load, rm_data.mode, rm_data.data_in);
    data_mismatch++;
    end
    cov_data = new rm_data;//sc
  //cov_data =  rm_data;
 

    coverage.sample();
    data_verified++;
    if (data_verified == rm_data.no_of_transactions) begin
      ->DONE;
   end
  endtask

  virtual task start();
    fork
      forever begin
        rm2sb.get(rm_data);
        rd2sb.get(rcvd_data);
        check(rcvd_data);
      end
    join_none
  endtask

  function void report();
    $display("------ SCOREBOARD REPORT -------");
    $display("Matches     : %0d", data_match);
    $display("Mismatches  : %0d", data_mismatch);
    $display("Total       : %0d", data_verified);
    $display("Coverage    : %0.2f%%", coverage.get_coverage());
    $display("-------------------------------");
  endfunction
endclass

////////////////10. Environment

class counter_env;
  virtual counter_if.WR_DRV wr_drv_if;
  virtual counter_if.WR_MON wr_mon_if;
  virtual counter_if.RD_MON rd_mon_if;

  mailbox #(counter_trans) gen2wr = new;
  mailbox #(counter_trans) wr2rm = new;
  mailbox #(counter_trans) rd2sb = new;
  mailbox #(counter_trans) rm2sb = new;
   ///tb componets handles
  counter_gen gen_h;
  counter_write_drv wr_drv_h;
  counter_write_mon wr_mon_h;
  counter_read_mon rd_mon_h;
  counter_ref_mod ref_mod_h;
  counter_sb sb_h;

  function new(virtual counter_if.WR_DRV wr_drv_if,
               virtual counter_if.WR_MON wr_mon_if,
               virtual counter_if.RD_MON rd_mon_if);
    this.wr_drv_if = wr_drv_if;
    this.wr_mon_if = wr_mon_if;
    this.rd_mon_if = rd_mon_if;
  endfunction

  task build();
    gen_h =new(gen2wr);//mb addr
    wr_drv_h = new(wr_drv_if, gen2wr);//via,mba
    wr_mon_h = new(wr_mon_if, wr2rm);
    rd_mon_h = new(rd_mon_if, rd2sb);
    ref_mod_h = new(wr2rm, rm2sb);//2mba
    sb_h = new(rm2sb, rd2sb);
  endtask

  task start();
    gen_h.start();
    wr_drv_h.start();
    wr_mon_h.start();
    rd_mon_h.start();
    ref_mod_h.start();
    sb_h.start();
  endtask

  task stop();
    wait(sb_h.DONE.triggered);
  endtask

  task run();
    start();
    stop();
    sb_h.report();
  endtask
endclass


///////////////////11. Test

class counter_test;
  virtual counter_if.WR_DRV wr_drv_if;
  virtual counter_if.WR_MON wr_mon_if;
  virtual counter_if.RD_MON rd_mon_if;

  counter_env env_h;

  function new(virtual counter_if.WR_DRV wr_drv_if,
               virtual counter_if.WR_MON wr_mon_if,
               virtual counter_if.RD_MON rd_mon_if);
    this.wr_drv_if = wr_drv_if;
    this.wr_mon_if = wr_mon_if;
    this.rd_mon_if = rd_mon_if;
    env_h = new(wr_drv_if, wr_mon_if, rd_mon_if);
  endfunction

  virtual task build_and_run();
    env_h.build();
    env_h.run();
    $finish;
  endtask
endclass


/////////////////////// 12. Top Module

module top;
  parameter cycle = 10;
  bit clk;

  counter_if DUV_IF(clk);

  counter_test test_h;

  counter_MOD12 dut (
    .clk(clk),
    .rst(DUV_IF.rst),
    .mode(DUV_IF.mode), 
    .load(DUV_IF.load),
    .data_in(DUV_IF.data_in),
    .data_out(DUV_IF.data_out)
  );

  initial begin
    test_h = new(DUV_IF, DUV_IF, DUV_IF);
    test_h.build_and_run();
  end

  // Clock Generation
  initial begin
    clk = 1'b0;
    forever #(cycle/2) clk = ~clk;
  end
endmodule