pragma circom 2.0.0;
include "../circuits/mux1.circom";
include "../circuits/comparators.circom";
include "../hasherPoseidon.circom";
include "./calculateTotal.circom";
include "./checkRoot.circom";

// This file contains circuits for quintary Merkle tree verifcation.
// It assumes that each node contains 5 leaves, as we use the PoseidonT6
// circuit to hash leaves, which supports up to 5 input elements.

/*
Note: circom has some particularities which limit the code patterns we can use.

- You can only assign a value to a signal once.
- A component's input signal must only be wired to another component's output
  signal.
- Variables can store linear combinations, and can also be used for loops,
  declaring sizes of things, and anything that is not related to inputs of a
  circuit.
- The compiler fails whenever you try to mix invalid elements.
- You can't use a signal as a list index.
*/

/*
 * Given a list of items and an index, output the item at the position denoted
 * by the index. The number of items must be less than 8, and the index must
 * be less than the number of items.
 */
template QuinSelector(choices,c1) {
    signal input in[choices][c1];
    signal input index1;
    signal input index2;
    

    signal output out;
    
    // Ensure that index < choices
    component lessThan = LessThan(8);
    lessThan.in[0] <== index1;
    lessThan.in[1] <== choices;
    lessThan.out === 1;

    component lessThan1 = LessThan(8);
    lessThan1.in[0] <== index2;
    lessThan1.in[1] <== c1;
    lessThan1.out === 1;

    component calcTotal = CalculateTotal(choices*c1);
    component eqs[choices*c1];
    
    log("index1",index1,"index2",index2);



    // For each item, check whether its index equals the input index.
    for (var i = 0; i < choices; i ++) {
        for(var j=0;j<c1;j++){
            eqs[i*c1+j] = IsEqual();
            eqs[i*c1+j].in[0] <== i;
            eqs[i*c1+j].in[1] <== index1;
            eqs[i*c1+j].in[2] <== j;
            eqs[i*c1+j].in[3] <== index2;

            //log("i",i,"j",j);
            //log(eqs[i*c1+j].out);
            //log(in[i][j]);
            calcTotal.nums[i*c1+j] <== eqs[i*c1+j].out * in[i][j];
        }
        // eqs[i].out is 1 if the index matches. As such, at most one input to
        // calcTotal is not 0.
        
    }

    // Returns 0 + 0 + ... + item
    out <== calcTotal.sum;
}

template QuinSelector_single(choices) {
    signal input in[choices];
    signal input index;
    signal output out;
    
    // Ensure that index < choices
    component lessThan = LessThan(3);
    lessThan.in[0] <== index;
    lessThan.in[1] <== choices;
    lessThan.out === 1;

    component calcTotal = CalculateTotal(choices);
    component eqs[choices];

    // For each item, check whether its index equals the input index.
    for (var i = 0; i < choices; i ++) {
        eqs[i] = IsEqual();
        eqs[i].in[0] <== i;
        eqs[i].in[1] <== index;

        // eqs[i].out is 1 if the index matches. As such, at most one input to
        // calcTotal is not 0.
        calcTotal.nums[i] <== eqs[i].out * in[i];
    }

    // Returns 0 + 0 + ... + item
    out <== calcTotal.sum;
}


