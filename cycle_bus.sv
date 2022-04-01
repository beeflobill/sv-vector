`timescale 1ns/1ps

module cycle_bus
#(
   parameter string name = "default_cycle_bus",
   parameter int    w    = 1
)
(  inout [w-1:0] X);

   cycle_if cif[w]();

   initial Cycle::register_bus(name, w);

   genvar i;
   generate
      for(i=0;i<w;i++) begin
         bufif1 (X[i], cif[i].X_out, cif[i].X_drive);
         assign cif[i].X_in = X[i];
         initial Cycle::register(Cycle::bus_name(name,i), cif[i]);
      end

   endgenerate

   //This should be part of registry, but I cound't figure out how to guarantee
   //the pin order when using the generate blocks
   initial begin
      for(int j=0; j<w; j++) begin
         Cycle::pin_order.push_back(Cycle::bus_name(name,j));
      end
   end


endmodule
