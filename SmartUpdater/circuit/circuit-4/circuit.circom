pragma circom 2.0.0;

include "circuits/keccak.circom";

//component main = Keccak(534*8+4, 32*8);

component main = Keccak(664, 32*8);//32*8是输出256位
//component main = Keccak(4270, 32*8);//32*8是输出256位
