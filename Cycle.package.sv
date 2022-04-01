`timescale 1ns/1ps
interface  cycle_if;
   logic X_out;
   wire  X_in;
   logic X_drive;
endinterface

package Cycle;
   timeunit      1ns;
   timeprecision 1ps;

   typedef  enum {
      dut_input,
      dut_output,
      dut_inout
   } Dir ;

   typedef struct {
      string name;

      enum {
          nrz,  //Non return to zero
          rz,   //Return to zero
          r1    //Return to 1
      } ts_type ;

      Dir dir; // Duuurrrr direction

      time t_sample;         //The dut is the output
      time t_drive;
      time t_drive_ret;
   } Timeset;

   typedef struct {
      time t_cycle;
      Timeset ts [string]; // index by pin name
   } Timeplate;

   typedef enum {
      DRIVE_1        , 
      DRIVE_0        , 
      DRIVE_Z        , 
      EXPECT_1       , 
      EXPECT_0       , 
      EXPECT_Z       , 
      EXPECT_NOTHING ,
      EXPECT_SAMPLE  
   } PinState;

   Timeplate timeplates[string]; //index by time plate names

   class Pin;
      virtual cycle_if cif;
      string name;

      logic v_drive;
      PinState v_expect;
      logic v_sample;
      PinState state;

      Timeset ts;

      function new(string name, virtual cycle_if cif);
         this.cif   = cif;
         this.name  = name;
         this.v_expect = EXPECT_SAMPLE;
         this.cif.X_drive = 1'b0;
         this.v_drive=1'bz;
      endfunction

      task cycle;
         logic turnaround_cycle;
         turnaround_cycle = 0;

         //The timing will be broken if the # delays inside of
         //blocks.  So, everything carefully written to have the # out in front
         //so it's not in the blocks.
         fork
            #ts.t_drive begin
               cif.X_out = v_drive;

               if (cif.X_drive!==0 && v_drive === 1'bz) begin
                  cif.X_drive = 0;
                  turnaround_cycle = 1;
               end

               if (v_drive!==1'bz) begin
                  cif.X_drive = 1;
               end
            end

            //This is probaby what a tester would do. This might seem to not matter,
            //but this comes into play when changing timeplates.
            //The vector file time specifications need to be written to match.
            #0ns begin
               if (ts.ts_type == rz) cif.X_out = 0; 
               if (ts.ts_type == r1) cif.X_out = 1;
            end

            #ts.t_drive_ret begin
               if (ts.ts_type == rz) cif.X_out = 0;
               if (ts.ts_type == r1) cif.X_out = 1;
            end

            #ts.t_sample begin
               v_sample = cif.X_in;

               //Gotta do it in time
               //No denyen
               //The pain, missen the frame
               //No cryin
               if (cif.X_drive==1 || turnaround_cycle==1) begin
                  if (v_drive===1'b0) state = DRIVE_0;
                  if (v_drive===1'b1) state = DRIVE_1;
                  if (v_drive===1'bz) state = DRIVE_Z;
               end
               else if (v_expect==EXPECT_SAMPLE && cif.X_drive==0) begin
                  if (v_sample===1'b0) state = EXPECT_0;
                  if (v_sample===1'b1) state = EXPECT_1;
                  if (v_sample===1'bz) state = EXPECT_Z;
                  if (v_sample===1'bx) state = EXPECT_NOTHING;
               end
               else begin
                  state = v_expect;
               end

            end
         join_none
      endtask
   endclass 

   Pin pins[string];
   int bus_size[string];

   string pin_order[$];

   function void register(string name, virtual cycle_if cif);
      $display("Registering pin: %s", name);
      if (pins.exists(name))
         $display("   Warning, pin %s already exists, can't register pin", name);
      else begin
         pins[name] = new(name, cif);
      end
   endfunction

   //For pin_order to have the correct order, this needs to be called in the right order.
   function void register_bus(string name, int size);
      $display("Registering bus: %s[%0d:0]", name, size-1);
      bus_size[name] = size;
   endfunction

   //We're detecting if these are busses and doing the work
   //in these tasks to apply the action to the entire bus,
   //if it exists.  This might be ugly, but it ultamently
   //hides the ugliness from the user so they don't have
   //to worry about it.
   function string bus_name (string name, int w);
      string s;
      $sformat(s, "%s[%0d]", name, w);
      return s;
   endfunction


   function void set_drive(string name, int val);
      if (bus_size.exists(name) == 1'b1) begin
         for(int i=0; i<bus_size[name]; i++) begin
            pins[bus_name(name,i)].v_drive = val[i];  //This is blind luck that it worked.  It could go backwards.
         end
      end
      else begin
         if (pins.exists(name) == 1'b0)
            $display("Error calling set_drive with pin/bus that doesn't exist: %s", name);
         pins[name].v_drive = val[0];
      end
   endfunction

   function void set_z(string name);
      if (bus_size.exists(name)) begin
         for(int i=0; i<bus_size[name]; i++) begin
            pins[bus_name(name,i)].v_drive = 1'bz;
         end
      end
      else begin
         if (!pins.exists(name))
            $display("Error calling set_z with pin/bus that doesn't exist: %s", name);
         pins[name].v_drive = 1'bz;
      end
   endfunction

   function void set_expect(string name, PinState val);
      if (bus_size.exists(name) == 1'b1) begin
         for(int i=0; i<bus_size[name]; i++) begin
            pins[bus_name(name,i)].v_expect = val; 
         end
      end
      else begin
         if (pins.exists(name) == 1'b0)
            $display("Error calling set_expect with pin/bus that doesn't exist: %s", name);
         pins[name].v_expect = val;
      end
   endfunction



   function logic[31:0] get(string name);
      logic [31:0] val;

      val = 0;
      if (bus_size.exists(name) == 1'b1) begin
         for(int i=0; i<bus_size[name]; i++) begin
            val[i] = pins[bus_name(name,i)].v_sample;  //This is blind luck that it worked.  It could go backwards.
         end
      end
      else begin
         if (pins.exists(name) == 1'b0)
            $display("Error calling set with pin/bus that doesn't exist: %s", name);
         val[0] = pins[name].v_sample;
      end

      return val;
   endfunction

   string active_tp;

   function void use_tp(string tp_name);
      active_tp = tp_name;
      foreach(pins[i]) begin
         pins[i].ts = timeplates[active_tp].ts[i] ;
      end
   endfunction

   class Printer;
      string fname;
      int fd;
      string pins[$];
      Timeplate tps[string];
      time creation_time;

      logic comment_flag;
      string s_comment;

      typedef Dir PinDirs[string]; //This is weird syntax, but okay.
      PinDirs dirs;

      string pin_order[$]; //This pin list can be used to get a better pin ordering.  It can be overridden with a custom list

      PinDirs ins;
      PinDirs outs;
      PinDirs inouts;

      function new(string fname, Timeplate tps[string], string pin_order[$]);
         this.fname = fname;
         this.tps = tps;

         creation_time = $realtime();

         dirs = get_pin_directions(this.tps);
         ins = filter_PinDirs(dut_input, dirs);
         outs = filter_PinDirs(dut_output, dirs);
         inouts = filter_PinDirs(dut_inout, dirs);

         this.pin_order = pin_order; //We would build this, but it's easier to build it during registration

         clear_comment();

         fd = $fopen(fname, "w");
         //$display("Writing %s", fname);
         print_top();
      endfunction

      function time get_time();
         return $realtime() - creation_time;
      endfunction

      //The Printer extensions will have to deal with comments
      //if that's what they feel like doing.
      function void comment(string new_comment);
         if (comment_flag==0)
            s_comment = new_comment;
         else
            s_comment = {s_comment, " & ", new_comment};

         comment_flag = 1'b1;        //Clear this when the comment is dealt with
      endfunction

      function void clear_comment();
         comment_flag = 1'b0;        //Clear this when the comment is dealt with
         s_comment = "";
      endfunction


      virtual function void print_top();
      endfunction

      virtual function void print_cycle(string tp_name, PinState pinStates [string]);
      endfunction

      virtual function void print_bottom();
      endfunction

      function void finish();
         print_bottom();
         $fclose(fd);
      endfunction


      function PinDirs get_pin_directions(Timeplate tps[string]);
         PinDirs dirs;
         Dir dir_tmp;
         string pin_name;

         foreach(tps[tp_name]) begin
            foreach(tps[tp_name].ts[pin_name]) begin
               dir_tmp = tps[tp_name].ts[pin_name].dir;

               if (dir_tmp == dut_inout)
                  $display("Warning, pin %s direction in timeset %s is inout.  Timesets should have dir either dut_input or dut_output.",
                     pin_name, tps[tp_name].ts[pin_name].name);

               if (dirs.exists(pin_name) == 1'b0) 
                  dirs[pin_name] = dir_tmp;
               else begin
                  if (dirs[pin_name] != dir_tmp)
                     dirs[pin_name] = dut_inout;
               end
            end
         end

         return dirs;
      endfunction

      function PinDirs filter_PinDirs(Dir dir_filter, PinDirs pins);
         PinDirs filtered;
         string pinname;

         foreach(pins[pinname]) begin
            if (pins[pinname] == dir_filter)
               filtered[pinname] = dir_filter;
         end
         return filtered;
      endfunction
   endclass


   class Printer_wgl extends Printer;
      function new(string fname, Timeplate tps[string], string pin_order[$]);
         super.new(fname, tps, pin_order);
      endfunction

      function void print_top();
         print_header();
         print_signals();
         print_timeplates();
      endfunction

    
      function void print_header();
         $fdisplay(fd, "waveform  \"TEST\"");
         $fdisplay(fd, "");
      endfunction

      function void print_signals();
         PinDirs dirs;
         string dir_string;

         $fdisplay(fd, "signal");
         
         //Print out pin with directions
         foreach(dirs[pin_name]) begin
            if (dirs[pin_name] == dut_input)  dir_string = "input";
            if (dirs[pin_name] == dut_output) dir_string = "output";
            if (dirs[pin_name] == dut_inout)  dir_string = "bider";
            $fdisplay(fd, "  \"%s\" : %s ;", pin_name, dir_string);
         end

         $fdisplay(fd, "end\n");
      endfunction

      function void print_timeplates();
         string pin;
         foreach(tps[tp]) begin
            $fdisplay(fd, "timeplate \"%s\" period %0tNS", tp, tps[tp].t_cycle); 
            
            foreach(pin_order[i]) begin
               pin = pin_order[i];
               $fdisplay(fd, "   \"%s\" := %s[timejunk]", pin, "input");
            end
            $fdisplay(fd, "end\n");
         end
      endfunction
   
      function void cycle_data;
      endfunction
   endclass

   class Printer_stil extends Printer;
      //This is the STIL reference doc: 
      //   IEEE Standard Test Interface Language (STIL for Digital Test Vector Data
      //   IEEE Std 1450-1999(R2011)
      //   This is a surprisingly well written spec.  I recommend it.
      //
      //   Another source of really good info is the VTRAN spec at synopsys.
      //   VTRAN is really the vehicle for testing this.

      string active_tp;


      function new(string fname, Timeplate tps[string], string pin_order[$]);
         super.new(fname, tps, pin_order);
         active_tp = "";
      endfunction

      function void print_top();
         $fdisplay(fd, "STIL 1.0 ;\n");

         $fdisplay(fd, "Header {");
         $fdisplay(fd, "   Title \"%s\" ;", fname);
         $fdisplay(fd, "   Date  \"\" ;");
         $fdisplay(fd, "   Source \"SV Class Printer_stil, version 0.2\";");
         $fdisplay(fd, "}\n");

         print_signals();
         print_siggroups();
         print_timing();
         print_burst();
         print_patternexec();
         print_pattop();
      endfunction

      function void print_bottom();
         $fdisplay(fd, "}\n");
      endfunction

      function void print_signals();
         string dir_string;

         $fdisplay(fd, "Signals {");
         
         foreach (pin_order[i]) if (ins.exists   (pin_order[i])) $fdisplay(fd, "  \"%s\" %s ;", pin_order[i], "In");
         foreach (pin_order[i]) if (outs.exists  (pin_order[i])) $fdisplay(fd, "  \"%s\" %s ;", pin_order[i], "Out");
         foreach (pin_order[i]) if (inouts.exists(pin_order[i])) $fdisplay(fd, "  \"%s\" %s ;", pin_order[i], "InOut");

         $fdisplay(fd, "}\n");
      endfunction

      //Helps print_siggroups put all the pin names together like:  "pina + pinb + pinc"
      function string group_string(PinDirs group);
         string lastpin;
         string s;
         string pinname;

         //Create a list with the group pins 
         //in order of pin_order
         string pinlist[$];
         foreach(pin_order[i]) begin
            if (group.exists(pin_order[i]))
               pinlist.push_back(pin_order[i]);
         end

         lastpin = pinlist[pinlist.size()-1];  //lastpin is being written here

         s = "";

         foreach(pinlist[i]) begin
            pinname = pinlist[i];
            if (pinname == lastpin) begin
               s = {s, pinname};
            end
            else begin
               s = {s, pinname, " + "};
            end
         end

         s = {"'", s, "'"};
         return s;
      endfunction

      function void print_siggroups();
         string gs;


         $fdisplay(fd, "SignalGroups {");

         if (ins.size() != 0) begin
            gs = group_string(ins);
            $fdisplay(fd, "   group_in = %s ;", gs);
         end

         if (outs.size() != 0) begin
            gs = group_string(outs);
            $fdisplay(fd, "   group_out = %s ;", gs);
         end
         
         if (inouts.size() != 0) begin
            gs = group_string(inouts);
            $fdisplay(fd, "   group_inout = %s ;", gs);
         end

         $fdisplay(fd, "}\n");
      endfunction

      function string make_driving_descriptor(Timeset ts);
         string s;

         //The leading 0ns in the time descriptions may seem meaningless, but
         //they take effect when the timeplate switches.  This is how the
         //timing in cycle is implemented.  Ultimantly, this needs to
         //match that. 
         if (ts.ts_type == nrz) begin
            $sformat(s, "{ 10ZN { '%0tps' U/D/Z/N; } }", ts.t_drive ); 
         end
         else if (ts.ts_type == rz) begin
            $sformat(s, "{ 01ZN { '0ps' D; '%0tps' D/U/Z/N; '%0tps' D; } }", ts.t_drive, ts.t_drive_ret );
         end
         else if (ts.ts_type == r1) begin
            $sformat(s, "{ 10ZN { '0ps' U; '%0tps' U/D/Z/N; '%0tps' U; } }", ts.t_drive, ts.t_drive_ret );
         end

         return s;
      endfunction

      function string make_sampling_descriptor(Timeset ts);
         string s;
         $sformat(s, "{ HLXT { '0ps' X; '%0tps' H/L/X/T; } }", ts.t_sample );
         return s;
      endfunction


      function void print_timing();
         string s;
         string pin_name;
         $fdisplay(fd, "Timing {");

         foreach(tps[tp_name]) begin
            $fdisplay(fd, "   WaveformTable %s {", tp_name);
            $fdisplay(fd, "      Period '%0tps' ;", tps[tp_name].t_cycle);
            $fdisplay(fd, "      Waveforms {");

            //This means that the .ts[pin_name] must have elements which match pin_order
            foreach(pin_order[i]) begin
               pin_name = pin_order[i];
               if ((dirs[pin_name] == dut_output) || (dirs[pin_name] == dut_inout)) begin
                  s = make_sampling_descriptor(tps[tp_name].ts[pin_name]);
                  $fdisplay(fd, "         %s %s", pin_name, s);
               end
               if ((dirs[pin_name] == dut_input) || (dirs[pin_name] == dut_inout)) begin
                  s = make_driving_descriptor(tps[tp_name].ts[pin_name]);
                  $fdisplay(fd, "         %s %s", pin_name, s);
               end
            end

            $fdisplay(fd, "      }");
            $fdisplay(fd, "   }");
         end

         $fdisplay(fd, "}\n");
      endfunction

      function void print_burst();
         $fdisplay(fd, "PatternBurst \"_burst_\" {");
         $fdisplay(fd, "  PatList {");
         $fdisplay(fd, "    \"_pattern_\" { }");
         $fdisplay(fd, "   }");
         $fdisplay(fd, "}\n");
      endfunction

      function void print_patternexec();
         $fdisplay(fd, "PatternExec  {");
         $fdisplay(fd, "  PatternBurst \"_burst_\" ;");
         $fdisplay(fd, "}\n");
      endfunction

      function void print_pattop();
         $fdisplay(fd, "Pattern \"_pattern_\" {");
      endfunction

      typedef struct {
         string drive;
         string samp;
      } Vectors;


      function string mapPinState(PinState state);
         //make this a drive/expect pair
         case (state)
             DRIVE_1        : return "1";  
             DRIVE_0        : return "0";  
             DRIVE_Z        : return "Z";  
             EXPECT_1       : return "H";  
             EXPECT_0       : return "L";  
             EXPECT_Z       : return "T";  
             EXPECT_NOTHING : return "X"; 
         endcase
      endfunction

      function string make_vector(PinDirs pindirs, PinState pinStates[string]);
         string V;
         string t;
         string pinname;

         V = "";

         foreach(pin_order[i]) begin
            pinname = pin_order[i];
            if (pindirs.exists(pinname)) begin
               t = mapPinState(pinStates[pinname]);
               V = {V,t};
            end
         end
         return V;
      endfunction


      function void print_cycle(string tp_name, PinState pinStates [string]);
         string V;

         //Comments!  Yay.
         if (comment_flag) begin
            $fdisplay(fd, "//  %s", s_comment);
            clear_comment();
         end

         if (active_tp != tp_name) begin
            $fdisplay(fd, "   W %s;", tp_name);
            active_tp = tp_name;
         end
         $fdisplay(fd, "   V {   // %0t", get_time());

         if (ins.size() != 0) begin
            V = make_vector(ins, pinStates);
            $fdisplay(fd, "         group_in    = %s ;", V);
         end

         if (outs.size() != 0) begin
            V = make_vector(outs, pinStates);
            $fdisplay(fd, "         group_out   = %s ;", V);
         end

         if (inouts.size() != 0) begin
            V = make_vector(inouts, pinStates);
            $fdisplay(fd, "         group_inout = %s ;",  V);
         end
         
         $fdisplay(fd, "     }");
      endfunction
   endclass

   Printer printer_list[string];


   task init();
      Timeplate bus_tps[string]; 

      #0; //Make sure all other initial blocks run before this
      
      //Expand busses in the time plates sent to the printer...there
      //ought to be a better way to manage this.  This info should just
      //be available in some data structure without having to do this
      //switcharoo.
      foreach(timeplates[tp_name]) begin
         bus_tps[tp_name].t_cycle = timeplates[tp_name].t_cycle;

         if (timeplates[tp_name].t_cycle == 0) begin
            $display("Warning, the timeplate %s has t_cycle=0ns.", tp_name); //This warning doesn't seem to work
         end

         //$display("init tp=%s", tp_name);
         foreach(timeplates[tp_name].ts[pin_name]) begin
            if (bus_size.exists(pin_name)) begin
               for(int i=0; i< bus_size[pin_name]; i++)
                  bus_tps[tp_name].ts[bus_name(pin_name,i)] = timeplates[tp_name].ts[pin_name];
            end
            else begin
               //$display("Doing pin conversion.  pin=%s  direction=%0d   ts=%s", pin_name, timeplates[tp_name].ts[pin_name].dir, timeplates[tp_name].ts[pin_name].name); 
               bus_tps[tp_name].ts[pin_name] = timeplates[tp_name].ts[pin_name];
            end
         end
      end
    
      //make the stupid thing work
      timeplates = bus_tps;  //Maybe do this in future to simplify the snot out of everything
   endtask

   function void open_printer(string s_file, string p_type);
      Printer_stil p_stil;
      Printer_wgl  p_wgl;

      if (printer_list.exists(s_file))
         $display("Warning, creating a stil printer which already exists: %s", s_file);
      $display("Opening and starting file: %s", s_file);

      if (p_type=="wgl") begin
         p_wgl = new(s_file, timeplates, pin_order);
         printer_list[s_file] = p_wgl;
      end
      else if (p_type=="stil") begin
         p_stil = new(s_file, timeplates, pin_order);
         printer_list[s_file] = p_stil;
      end
   endfunction

   function void close_printer(string s_file);
      if (!printer_list.exists(s_file))
         $display("Warning, trying to close wgl printer which doesn't exist: %s", s_file);
      else begin
         $display("Finishing and closing file: %s", s_file);
         printer_list[s_file].finish();
         printer_list.delete(s_file);
      end
   endfunction


   function void close_all();
      foreach (printer_list[s_file]) begin
         close_printer(s_file);
      end
   endfunction


   function void comment(string txt);
      foreach (printer_list[s_file])
         printer_list[s_file].comment(txt);
   endfunction


   //Call all the pin cycle tasks
   //  These are using fork...join_none to make
   //  all the tasks concurrent even though they are being
   //  called from a loop.  Thus, we need wait fork to bring
   //  it all back together.  Just try and find another way to do this.
   task cycle;
      string pinname;
      PinState pinState [string];
      time t_cycle;

      t_cycle = timeplates[active_tp].t_cycle; //This gets us our cycle time

      fork
         #t_cycle;
         foreach(pins[i])
            pins[i].cycle();   //These use join_none, so we have to call wait fork to get all back together.
      join
      wait fork;

      //This is more work than it should be.
      //TODO rework how Pins are organized.  I shouldn't have to extract this.
      //It should just exist in the data structure.
      foreach(pin_order[i]) begin
         pinname = pin_order[i];
         pinState[pinname] = pins[pinname].state;
      end
      
      foreach(printer_list[s_file])
        printer_list[s_file].print_cycle(active_tp, pinState);
   endtask

endpackage
