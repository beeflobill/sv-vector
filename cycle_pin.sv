`timescale 1ns/1ps

module cycle_pin
#(
   parameter string name = "default_cycle_pin"
)
(
   inout X
);

   cycle_if cif();

   bufif1 (X, cif.X_out, cif.X_drive);
   assign cif.X_in = X;

   initial begin
      Cycle::register(name, cif);
      Cycle::pin_order.push_back(name);
   end
endmodule
