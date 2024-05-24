/* -*- P4_16 -*- */

/*
 * P4 Algo Trader
 *
 * This program implements a simple protocol. It can be carried over Ethernet
 * (Ethertype 0x1234).
 *
 * The Protocol header looks like this:
 *
 *        0                1                  2              3
 * +----------------+----------------+----------------+
 * |      P         |       4        |     Version    |
 * +----------------+----------------+----------------+---------------+
 * |                            Action (act)                          |
 * +----------------+----------------+----------------+---------------+
 * |                   Amount of shares to trade (amt)                |
 * +----------------+----------------+----------------+---------------+
 * |                      Market price (mktprice)                     |
 * +----------------+----------------+----------------+---------------+
 * |                              cmpAvg                              |
 * +----------------+----------------+----------------+---------------+
 * |          Short term moving average (last 4 trades) (mAvgS)       |
 * +----------------+----------------+----------------+---------------+
 * |         Medium term moving average (last 4 trades) (mAvgM)       |
 * +----------------+----------------+----------------+---------------+
 * |          Long term moving average (last 16 trades) (mAvgL)       |
 * +----------------+----------------+----------------+---------------+
 * |                          Trade count (tc)                        |
 * +----------------+----------------+----------------+---------------+
 *
 * P is an ASCII Letter 'P' (0x50)
 * 4 is an ASCII Letter '4' (0x34)
 * Version is currently 0.1 (0x01)
 * act is the action to take:
 *   0 = no trade advised
 *   1 = buy
 *   2 = sell
 *
 * cmpAvg is 4 bits of data: (TRIPLE moving average price crossover strategy)
 * +------------------+------------------+------------------+------------------+
 * |                           mAvgS as compared to:                           |
 * +------------------+------------------+------------------+------------------+--------+
 * | mAvgM last trade | mAvgL last trade | mAvgM this trade | mAvgL this trade | action |
 * +------------------+------------------+------------------+------------------+--------+
 * | 0 (lower)        | 1 (higher)       | 1 (higher)       | 1 (higher)       | BUY    |
 * +------------------+------------------+------------------+------------------+--------+
 * | 1 (higher)       | 0 (lower)        | 0 (lower)        | 0 (lower)        | SELL   |
 * +------------------+------------------+------------------+------------------+--------+
 * | all other combinations                                                    |no trade|
 * +------------------+------------------+------------------+------------------+--------+
 *
 * The device receives a packet, determines the action and amount of shares to trade,
 * and sends the packet back out of the same port it came in on,
 * while swapping the source and destination addresses.
 *
 * If an unknown operation is specified or the header is not valid, the packet
 * is dropped
 */

#include <core.p4>
#include <v1model.p4>

/*
 * Define the headers the program will recognize
 */

/*
 * Standard Ethernet header
 */
header ethernet_t {
    bit<48> dstAddr;
    bit<48> srcAddr;
    bit<16> etherType;
}

/*
 * This is a custom protocol header for the calculator. We'll use
 * etherType 0x1234 for it (see parser)
 */
const bit<16> P4TRADE_ETYPE = 0x1234;
const bit<8>  P4TRADE_P     = 0x50;   // 'P'
const bit<8>  P4TRADE_4     = 0x34;   // '4'
const bit<8>  P4TRADE_VER   = 0x01;   // v0.1

header p4trade_t {
    bit<8>  p;
    bit<8>  four;
    bit<8>  ver;
    bit<32>  act;
    bit<32>  amt;
    bit<32>  mktprice;
    bit<32> cmpAvg;
    bit<32> mAvgS;
    bit<32> mAvgM;
    bit<32> mAvgL;
    bit<32> tc;
}

/*
 * All headers, used in the program needs to be assembled into a single struct.
 * We only need to declare the type, but there is no need to instantiate it,
 * because it is done "by the architecture", i.e. outside of P4 functions
 */
struct headers {
    ethernet_t   ethernet;
    p4trade_t     p4trade;
}

/*
 * All metadata, globally used in the program, also  needs to be assembled
 * into a single struct. As in the case of the headers, we only need to
 * declare the type, but there is no need to instantiate it,
 * because it is done "by the architecture", i.e. outside of P4 functions
 */

struct metadata {
    /* In our case it is empty */
}

// initialise register to store market prices history
register<bit<32>>(8192) priceHist;

// initialise counter
register<bit<32>>(8192) tradeCountReg;

// initialise register to store if the last AvgS was higher than AvgM
register<bit<1>>(1) SMlastReg;

// initialise register to store if the last AvgS was higher than AvgL
register<bit<1>>(1) SLlastReg;

/*************************************************************************
 ***********************  P A R S E R  ***********************************
 *************************************************************************/
parser MyParser(packet_in packet,
                out headers hdr,
                inout metadata meta,
                inout standard_metadata_t standard_metadata) {
    state start {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            P4TRADE_ETYPE : check_p4trade;
            default      : accept;
        }
    }

    state check_p4trade {
        
        transition select(packet.lookahead<p4trade_t>().p,
        packet.lookahead<p4trade_t>().four,
        packet.lookahead<p4trade_t>().ver) {
            (P4TRADE_P, P4TRADE_4, P4TRADE_VER) : parse_p4trade;
            default                          : accept;
        }
        
    }

    state parse_p4trade {
        packet.extract(hdr.p4trade);
        transition accept;
    }
}

/*************************************************************************
 ************   C H E C K S U M    V E R I F I C A T I O N   *************
 *************************************************************************/
control MyVerifyChecksum(inout headers hdr,
                         inout metadata meta) {
    apply { }
}

/*************************************************************************
 **************  I N G R E S S   P R O C E S S I N G   *******************
 *************************************************************************/
control MyIngress(inout headers hdr,
                  inout metadata meta,
                  inout standard_metadata_t standard_metadata) {
                  
    action send_back(bit<32> tradeAct, bit<32> tradeAmt) {
    
        hdr.p4trade.act = tradeAct; // put the action back in hdr.p4trade.act
        hdr.p4trade.amt = tradeAmt; // put the trade amount back in hdr.p4trade.amt
        
        /* swap MAC addresses in hdr.ethernet.dstAddr and
           hdr.ethernet.srcAddr using a temp variable */
        bit<48> tmp = hdr.ethernet.dstAddr;
        hdr.ethernet.dstAddr = hdr.ethernet.srcAddr;
        hdr.ethernet.srcAddr = tmp;
        
        /* Send the packet back to the port it came from
           by saving standard_metadata.ingress_port into
           standard_metadata.egress_spec */
        standard_metadata.egress_spec = standard_metadata.ingress_port;
    }

    action writePriceHist(bit<32> tradeCount) {
        priceHist.write(tradeCount, hdr.p4trade.mktprice);
    }
    action countTrades() {
        bit<32> tradeCountVar;
        tradeCountReg.read(tradeCountVar, 0);
        tradeCountVar = tradeCountVar + 1;
        tradeCountReg.write(0, tradeCountVar);
    }
    
    action calcMovingAvg(bit<32> tradeCount) {
        bit<32> recent0;
        bit<32> recent1;
        bit<32> recent2;
        bit<32> recent3;
        bit<32> recent4;
        bit<32> recent5;
        bit<32> recent6;
        bit<32> recent7;
        bit<32> recent8;
        bit<32> recent9;
        bit<32> recent10;
        bit<32> recent11;
        bit<32> recent12;
        bit<32> recent13;
        bit<32> recent14;
        bit<32> recent15;
        
        priceHist.read(recent0, tradeCount);
        priceHist.read(recent1, tradeCount-1);
        priceHist.read(recent2, tradeCount-2);
        priceHist.read(recent3, tradeCount-3);
        priceHist.read(recent4, tradeCount-4);
        priceHist.read(recent5, tradeCount-5);
        priceHist.read(recent6, tradeCount-6);
        priceHist.read(recent7, tradeCount-7);
        priceHist.read(recent8, tradeCount-8);
        priceHist.read(recent9, tradeCount-9);
        priceHist.read(recent10, tradeCount-10);
        priceHist.read(recent11, tradeCount-11);
        priceHist.read(recent12, tradeCount-12);
        priceHist.read(recent13, tradeCount-13);
        priceHist.read(recent14, tradeCount-14);
        priceHist.read(recent15, tradeCount-15);
        
        bit<32> sum4recents = recent0 + recent1 + recent2 + recent3;
        bit<32> sum8recents = recent0 + recent1 + recent2 + recent3 + recent4 + recent5 + recent6 + recent7;
        bit<32> sum16recents = recent0 + recent1 + recent2 + recent3 + recent4 + recent5 + recent6 + recent7 + recent8 + recent9 + recent10 + recent11 + recent12 + recent13 + recent14 + recent15;
        hdr.p4trade.mAvgS = sum4recents >> 2;
        hdr.p4trade.mAvgM = sum8recents >> 3;
        hdr.p4trade.mAvgL = sum16recents >> 4;
    }
    
    action buy(bit<32> tradeAmt) {
        send_back(1, tradeAmt);
    }
    
    action sell(bit<32> tradeAmt) {
        send_back(2, tradeAmt);
    }
    
    action noTrade() {
        send_back(0, 0);
    }

    action operation_drop() {
        mark_to_drop(standard_metadata);
    }

    table tradeTable {
        key = {
            hdr.p4trade.cmpAvg        : exact;
        }
        actions = {
            buy;
            sell;
            noTrade;
            NoAction;
        }
        const default_action = noTrade();
        
        const entries = {
            7 : buy(1);
            8 : sell(1);
        }
    }

    apply {
        if (hdr.p4trade.isValid()) {
            countTrades();
            bit<32> tradeCount;
            tradeCountReg.read(tradeCount, 0);
            hdr.p4trade.tc = tradeCount;
            writePriceHist(tradeCount);
            if (tradeCount < 17) { 
            // moving avg will only be calculated if there are sufficient trades
                hdr.p4trade.cmpAvg = 0;
            }
            else {
                bit<1> SLlast; // boolean mAvgS > mAvgL, last trade etc.
                bit<1> SLnow = 0;
                bit<1> SMlast;
                bit<1> SMnow = 0;
                calcMovingAvg(tradeCount);
                SMlastReg.read(SMlast, 0); // read from regs
                SLlastReg.read(SLlast, 0);
                
                // compare moving averages
                if (hdr.p4trade.mAvgS > hdr.p4trade.mAvgL) {
                    SLnow = 1;
                }
                else if (hdr.p4trade.mAvgS < hdr.p4trade.mAvgL) {
                    SLnow = 0;
                }
                else {
                    SLnow = SLlast;
                }
                
                if (hdr.p4trade.mAvgS > hdr.p4trade.mAvgM) {
                    SMnow = 1;
                }
                else if (hdr.p4trade.mAvgS < hdr.p4trade.mAvgM) {
                    SMnow = 0;
                }
                else {
                    SMnow = SMlast;
                }
                // write comparisons with average to header
                bit<28> leadingZeros = 0;
                hdr.p4trade.cmpAvg = leadingZeros ++ SMlast ++ SLlast ++ SMnow ++ SLnow;
                
                // rewrite registers
                SMlastReg.write(0, SMnow);
                SLlastReg.write(0, SLnow);
            }
            tradeTable.apply();
        } 
        else {
            operation_drop();
        }
    }
}

/*************************************************************************
 ****************  E G R E S S   P R O C E S S I N G   *******************
 *************************************************************************/
control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {
    apply { }
}

/*************************************************************************
 *************   C H E C K S U M    C O M P U T A T I O N   **************
 *************************************************************************/

control MyComputeChecksum(inout headers hdr, inout metadata meta) {
    apply { }
}

/*************************************************************************
 ***********************  D E P A R S E R  *******************************
 *************************************************************************/
control MyDeparser(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.p4trade);
    }
}

/*************************************************************************
 ***********************  S W I T T C H **********************************
 *************************************************************************/

V1Switch(
MyParser(),
MyVerifyChecksum(),
MyIngress(),
MyEgress(),
MyComputeChecksum(),
MyDeparser()
) main;
