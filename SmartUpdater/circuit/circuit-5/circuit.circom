pragma circom 2.0.0;

include "circuits/keccak.circom";
include "circuits/comparators.circom";
template receipt(nlogs,max_ntopic){               
    signal input topic[64];
    signal input topic0[nlogs][max_ntopic][64];

    signal output out1[nlogs][max_ntopic];
    signal output out[nlogs];

    component check1[nlogs][max_ntopic][64];

    signal temp1[nlogs][max_ntopic];
    signal tempt[nlogs];

    for(var t=0;t< nlogs;t++){
        log("t=");
        log(t);
        var flagt = 0;
        for(var i=0;i< max_ntopic;i++){
            var flag = 1;
            for(var j=0;j<64;j++){
                check1[t][i][j] = IsEqual();    
                check1[t][i][j].in[0] <== topic[j];
                check1[t][i][j].in[1] <== topic0[t][i][j];

                flag = flag * check1[t][i][j].out;
            }
            
            flagt = flagt + flag;
            temp1[t][i] <-- flag;
            out1[t][i] <== temp1[t][i]; 
            log(out1[t][i]);
        }
        tempt[t] <-- flagt;
        out[t] <== tempt[t];
        log("out");
        log(tempt[t]);
    }
}

template Main() { 
    signal input topic[64];
    signal input topic0[3][64];

    signal output out1[3];

    component check1[3][64];

    signal temp1[3];

    
    for(var i=0;i<3;i++){
        var flag = 1;
        for(var j=0;j<64;j++){
            check1[i][j] = IsEqual();    
            check1[i][j].in[0] <== topic[j];
            check1[i][j].in[1] <== topic0[i][j];

            flag = flag * check1[i][j].out;
        }
        temp1[i] <-- flag;

        out1[i] <== temp1[i];  //不存在的=0
        log(out1[i]);
    }
}


component main = receipt(4,3);
