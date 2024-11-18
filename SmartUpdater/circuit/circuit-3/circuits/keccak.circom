// Keccak256 hash function (ethereum version).
// For LICENSE check https://github.com/vocdoni/keccak256-circom/blob/master/LICENSE

pragma circom 2.0.0;

include "./utils.circom";
include "./permutations.circom";
include "../circom/circuits/comparators.circom";

function div(a,b){
    var r = a;
    var q = 0;
    while (r >= b) {
        r = r - b;
        q = q + 1;
    }
    return q;
}

template Pad(nBits) {
    signal input in[nBits]; //nBits 4272 534*8 136
    var bs = 1088;
    var number = div(nBits,bs)+1; //4

    var blockSize= number*bs;  //4352 = 544*8
    
    signal output out[blockSize];
    signal out2[blockSize];

    var i;

    for (i=0; i<nBits; i++) {
        out2[i] <== in[i];
        
    }
    var domain = 0x01;
    for (i=0; i<8; i++) {
        out2[nBits+i] <== (domain >> i) & 1;
    }
    for (i=nBits+8; i<blockSize; i++) {
        out2[i] <== 0;
    }
    component aux = OrArray(8);
    for (i=0; i<8; i++) {
        aux.a[i] <== out2[blockSize-8+i];
        aux.b[i] <== (0x80 >> i) & 1;
    }
    for (i=0; i<8; i++) {
        out[blockSize-8+i] <== aux.out[i];
    }
    for (i=0; i<blockSize-8; i++) {
        out[i]<==out2[i];
    }
}

template KeccakfRound(r) {
    signal input in[25*64];
    signal output out[25*64];
    var i;

    component theta = Theta();
    component rhopi = RhoPi();
    component chi = Chi();
    component iota = Iota(r);

    for (i=0; i<25*64; i++) {
        theta.in[i] <== in[i];
    }
    for (i=0; i<25*64; i++) {
        rhopi.in[i] <== theta.out[i];
    }
    for (i=0; i<25*64; i++) {
        chi.in[i] <== rhopi.out[i];
    }
    for (i=0; i<25*64; i++) {
        iota.in[i] <== chi.out[i];
    }
    for (i=0; i<25*64; i++) {
        out[i] <== iota.out[i];
    }
}

template Absorb() {
    var blockSizeBytes=136;  //136

    signal input s[25*64];
    signal input block[blockSizeBytes*8];
    signal output out[25*64];
    var i;
    var j;

    component aux[blockSizeBytes/8];
    component newS = Keccakf();

    for (i=0; i<blockSizeBytes/8; i++) {
        aux[i] = XorArray(64);
        for (j=0; j<64; j++) {
            aux[i].a[j] <== s[i*64+j];
            aux[i].b[j] <== block[i*64+j];
        }
        for (j=0; j<64; j++) {
            newS.in[i*64+j] <== aux[i].out[j];
        }
    }
    // fill the missing s that was not covered by the loop over
    // blockSizeBytes/8
    for (i=(blockSizeBytes/8)*64; i<25*64; i++) {
            newS.in[i] <== s[i];
    }
    for (i=0; i<25*64; i++) {
        out[i] <== newS.out[i];
    }
}

template Final(nBits) {
    signal input in[nBits]; //
    signal output out[25*64];
    var blockSize=136*8;
    //var i;
    var padding = 544*8; //4*136*8

    // pad
    component pad = Pad(nBits);
    for (var i=0; i<nBits; i++) {
        pad.in[i] <== in[i];
    }
    // // absorb
    // //round1:p1
    // component abs1 = Absorb();
    // for (var i=0; i<blockSize; i++) {
    //     abs1.block[i] <== pad.out[i];
    // }
    // for (var i=0; i<25*64; i++) {
    //     abs1.s[i] <== 0;
    // }
    // padding = pad.out[2*blockSize];
    // //round2:p2
    // component abs2 = Absorb();
    // for (var i=0; i<blockSize; i++) {
    //     abs2.block[i] <== pad.out[i+blockSize];
    // }
    // for (var i=0; i<25*64; i++) {
    //     abs2.s[i] <== abs1.out[i];
    // }
    // //round3:p3
    // component abs3 = Absorb();
    // for (var i=0; i<blockSize; i++) {
    //     abs3.block[i] <== pad.out[i+2*blockSize];
    // }
    // for (var i=0; i<25*64; i++) {
    //     abs3.s[i] <== abs2.out[i];
    // }
    // //round4:p4
    // component abs4 = Absorb();
    // for (var i=0; i<blockSize; i++) {
    //     abs4.block[i] <== pad.out[i+3*blockSize];
    // }
    // for (var i=0; i<25*64; i++) {
    //     abs4.s[i] <== abs3.out[i];
    // }

    var bs = 1088;
    var number = div(nBits,bs)+1; //4
    
    component abs[number];
    abs[0] = Absorb();
    for (var i=0; i<blockSize; i++) {
        abs[0].block[i] <== pad.out[i];
    }
    for (var i=0; i<25*64; i++) {
        abs[0].s[i] <== 0;
    }

    for(var t=1;t<number;t++){
        abs[t] = Absorb();
        for (var i=0; i<blockSize; i++) {
            abs[t].block[i] <== pad.out[i+t*blockSize];
        }
        for (var i=0; i<25*64; i++) {
            abs[t].s[i] <== abs[t-1].out[i];
        }
    }

    for (var i=0; i<25*64; i++) {
        out[i] <== abs[number-1].out[i];
    }
}

template Squeeze(nBits) {
    signal input s[25*64];
    signal output out[nBits];
    var i;
    var j;

    for (i=0; i<25; i++) {
        for (j=0; j<64; j++) {
            if (i*64+j<nBits) {
                out[i*64+j] <== s[i*64+j];
            }
        }
    }
}

template Keccakf() {
    signal input in[25*64];
    signal output out[25*64];
    var i;
    var j;

    // 24 rounds
    component round[24];
    signal midRound[24*25*64];
    for (i=0; i<24; i++) {
        round[i] = KeccakfRound(i);
        if (i==0) {
            for (j=0; j<25*64; j++) {
                midRound[j] <== in[j];
            }
        }
        for (j=0; j<25*64; j++) {
            round[i].in[j] <== midRound[i*25*64+j];
        }
        if (i<23) {
            for (j=0; j<25*64; j++) {
                midRound[(i+1)*25*64+j] <== round[i].out[j];
            }
        }
    }

    for (i=0; i<25*64; i++) {
        out[i] <== round[23].out[i];
    }
}

template Keccak_ori(nBitsIn, nBitsOut) {  //原先只进行keccak的算法
    signal input in[nBitsIn];
    signal output out[nBitsOut];
    var i;

    component f = Final(nBitsIn);
    for (i=0; i<nBitsIn; i++) {
        f.in[i] <== in[i];
    }
    component squeeze = Squeeze(nBitsOut);
    for (i=0; i<25*64; i++) {
        squeeze.s[i] <== f.out[i];
    }
    for (i=0; i<nBitsOut; i++) {
        out[i] <== squeeze.out[i];
    }
}

template Keccak(nBitsIn, nBitsOut) {  //加上了hash比较
    signal input hash[256];
    signal input in[nBitsIn];
    //signal output out[nBitsOut];
    signal output out; //匹配成功 out = 1；
    //signal temp ;
    var i;

    component f = Final(nBitsIn);
    for (i=0; i<nBitsIn; i++) {
        f.in[i] <== in[i];
    }
    component squeeze = Squeeze(nBitsOut);
    for (i=0; i<25*64; i++) {
        squeeze.s[i] <== f.out[i];
    }
    //temp <== 1;
    component check[nBitsOut];
    var flag = 1;
    signal temp;
    for (i=0; i<nBitsOut; i++) {
        //out[i] <== squeeze.out[i];
        log("squeeze");
        log(squeeze.out[i]);
        log("hash");
        log(hash[i]);
        
        check[i] = IsEqual();    //相同的=1；不同的=0；
        check[i].in[0] <== hash[i];
        check[i].in[1] <== squeeze.out[i];
        flag = flag * check[i].out;
    }
    temp <-- flag;
    out <== temp;
    log(out);
}
