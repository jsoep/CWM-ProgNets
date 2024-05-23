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
 * +----------------+----------------+----------------+---------------+
 * |      P         |       4        |     Version    |  Action (act) |
 * +----------------+----------------+----------------+---------------+
 * |                   Amount of shares to trade (amt)                |
 * +----------------+----------------+----------------+---------------+
 * |                      Market price (mktprice)                     |
 * +----------------+----------------+----------------+---------------+
 *
 * P is an ASCII Letter 'P' (0x50)
 * 4 is an ASCII Letter '4' (0x34)
 * Version is currently 0.1 (0x01)
 * act is the action to take:
 *   0 = do nothing
 *   1 = buy
 *   2 = sell
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
    bit<8>  act;
    bit<32>  amt;
    bit<32>  mktprice;
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

// initialise register to store if the last trade price was higher, equal to or lower than moving average
register<bit<2>>(1) lastIsHigher; // 2 means higher than average, 1 means equal, 0 means lower

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
    action send_back(bit<8> tradeAct, bit<32> tradeAmt) {
    
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
    /*
    action count(bit<32> index) {
        c.count(index); // increment counter at index
    }
    */
    action writePriceHist(bit<32> tradeCount) {
        priceHist.write(tradeCount, hdr.p4trade.mktprice);
    }
    action countTrades() {
        bit<32> tradeCountVar;
        tradeCountReg.read(tradeCountVar, 0);
        tradeCountVar = tradeCountVar + 1;
        tradeCountReg.write(0, tradeCountVar);
    }
    
    action calcMovingAvg(out bit<32> movingAvg, in bit<32> tradeCount) {
        bit<32> recent0;
        bit<32> recent1;
        bit<32> recent2;
        bit<32> recent3;
        priceHist.read(recent0, tradeCount);
        priceHist.read(recent1, tradeCount-1);
        priceHist.read(recent2, tradeCount-2);
        priceHist.read(recent3, tradeCount-3);
        
        bit<32> sum4recents = recent0 + recent1 + recent2 + recent3;
        
        movingAvg = sum4recents >> 2;
    }
    
    action tooFewTrades() {
    
    }
    
    action decideTrade() {
        countTrades();
        bit<32> tradeCount;
        tradeCountReg.read(tradeCount, 0);
        writePriceHist(tradeCount);
        bit<8> tradeAct = 0; // do nothing by default
        bit<32> tradeAmt = 0;
        
        bit<32> movingAvg = calcMovingAvg(tradeCount);
            
        bit<2> lastTradeIsHigher; // than average
        bit<2> thisTradeIsHigher = 1; // than average; 1 means equal
        lastIsHigher.read(lastTradeIsHigher, 0); // read 0th index of lastIsHigher register
    
        // determine if current market price is higher or lower than moving average
        
        bit<2> HigherThanAvg = 2;
        bit<2> LowerThanAvg = 0;
        if (hdr.p4trade.mktprice > movingAvg) {
            thisTradeIsHigher = HigherThanAvg;
        }
        else if (hdr.p4trade.mktprice > movingAvg) {
            thisTradeIsHigher = LowerThanAvg;
        }
        
        // implement moving average crossover strategy
        if (lastTradeIsHigher == LowerThanAvg && thisTradeIsHigher == HigherThanAvg) {
            tradeAct = 1; //buy
            tradeAmt = 1;
        }
        else if (lastTradeIsHigher == HigherThanAvg && thisTradeIsHigher == LowerThanAvg) {
            tradeAct = 2; //sell
            tradeAmt = 1;
        }
        
        // rewrite lastIsHigher
        lastIsHigher.write(0, thisTradeIsHigher);
        
        // call send_back
        send_back(tradeAct, tradeAmt);
    }
    
    action buy(tradeAmt) {
        send_back(1, tradeAmt);
    }
    
    action sell(tradeAmt) {
        send_back(2, tradeAmt);
    }
    
    action doNothing() {
        send_back(0, 0);
    }

    action operation_drop() {
        mark_to_drop(standard_metadata);
    }

    table tradeTable {
        key = {
            hdr.p4trade.mktprice        : exact; //dummy
        }
        actions = {
            buy;
            sell;
            doNothing;
            NoAction;
            
        }
        const default_action = decideTrade();
        /*
        const entries = {
            P4CALC_PLUS : buy();
            P4CALC_MINUS: sell();
            P4CALC_AND  : doNothing();
        }
        */
    }

    apply {
        if (hdr.p4trade.isValid()) {
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
