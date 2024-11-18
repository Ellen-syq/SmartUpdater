pragma circom 2.0.0;
include "other-circuit/circuits/bitify.circom";
include "other-circuit/circuits/binsum.circom";
include "other-circuit/trees/incrementalQuinTree.circom";
include "other-circuit/keccak/keccak.circom";


template index(){
    signal input a;
    signal output out;

    component bit8 = Num2Bits(8);
    bit8.in <== a;

    var and8[8] = [0,0,0,0,0,0,0,0];  
    for(var i=0;i<3;i++){   
       if(bit8.out[i] == 1){
          and8[i] = 1;
       }
    }

    component num8 = Bits2Num(8);
    component less[8];
    for(var i=0;i<8;i++){
       num8.in[i] <-- and8[i];
       less[i] = LessThan(3);
       less[i].in[0] <== i;
       less[i].in[1] <== 8;
       less[i].out === 1;
    }
    var index = num8.out;

    out<==index;
}

template byte(){
    signal input a;
    signal output out;
    
    component bit16 = Num2Bits(16);  //数字转成二进制
    bit16.in <== a;
    for(var i=0;i<16;i++){
      log(bit16.out[i]);
    }

    var and16[16];
    for(var i=0;i<16;i++){ 
       and16[i] = 0;
    }

    for(var i=0;i<11;i++){  
       if(bit16.out[i] == 1){
          and16[i] = 1;
       }
    }


    var B[16];
    for(var i=0;i<16;i++){  
       B[i] = 0;
    }
    for(var i=0;i<13;i++){   
       B[i] = and16[i+3];
    }

    component num16 = Bits2Num(16);   //二进制转成数字
    component less[16];

    for(var i=0;i<16;i++){
      num16.in[i] <-- B[i];
      less[i] = LessThan(4);
      less[i].in[0] <== i;
      less[i].in[1] <== 16;
      less[i].out === 1;
       
    }

    var byte = 256 - num16.out -1;

    out<==byte;
}


template Main() {
   signal  input topic[256];  
   signal  input bloom[256][2];

   signal output out;

   var topics[3][2];


   //keccak256
   component kec = Keccak_topics(256);
   for(var i=0;i<256;i++){
      kec.in[i] <== topic[i];
   }
   for(var i=0;i<3;i++){
      for(var j=0;j<2;j++){
         topics[i][j] = kec.out[i][j];
         log(topics[i][j]);
      }
   }


   //Bloom
   component Index[3] ;
   component Byte[3];

   var b[3];


   component quinSelector[3];
   
   component quinSelector2[3];


   component bit1[3];
   component bit2[3];

   for(var i=0;i<3;i++){
      Index[i] = index();
      Index[i].a <== topics[i][0];
      Byte[i] = byte();
      Byte[i].a <== topics[i][1];
      var I;
      var B;
      
      I = Index[i].out;    
      B = Byte[i].out;    
      log(I);
      log(B);

      var indexbit[8] = [0,0,0,0,0,0,0,0];

      var bl = 0;
      
      bit1[i] = Num2Bits(4);
      quinSelector[i] = QuinSelector(256,2);
      for (var k=0; k< 256; k++) {
         for (var q=0; q< 2; q++) {
               quinSelector[i].in[k][q] <== bloom[k][q];
         }
   }
      quinSelector[i].index1 <== B;
      quinSelector[i].index2 <== 0;

      bit1[i].in <== quinSelector[i].out;

   
      bit2[i] = Num2Bits(4);
      quinSelector2[i] = QuinSelector(256,2);
      for (var k=0; k< 256; k++) {
         for (var q=0; q< 2; q++) {
               quinSelector2[i].in[k][q] <== bloom[k][q];
         }
   }
      quinSelector2[i].index1 <== B;
      quinSelector2[i].index2 <== 1;

      
      bit2[i].in <== quinSelector2[i].out;
         
      var k1=3;
      for(var j=0;j<4;j++){
         indexbit[j] = bit1[i].out[k1];
         k1=k1-1;
      }
      var k2=3;
      for(var j=4;j<8;j++){
         indexbit[j] = bit2[i].out[k2];
         k2=k2-1;
      }
      
      b[i] = indexbit[8-1-I];

}


   var numb[3];
   component num1[3] ;   //二进制转成数字
   component less[3];
   for(var i=0;i<3;i++){
      num1[i]= Bits2Num(1);
      num1[i].in[0] <-- b[i];
      less[i] = LessThan(3);
      less[i].in[0] <== i;
      less[i].in[1] <== 3;
      less[i].out === 1;
      numb[i] = num1[i].out;
   }
   
   var sum = 0;
   for(var i=0;i<3;i++){
      sum = sum + numb[i];
   }


   component isz = IsZero();
   isz.in <== sum - 3;
   out <==isz.out;
    
	
}

component main = Main();
