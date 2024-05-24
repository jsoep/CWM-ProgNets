#!/usr/bin/env python3

import re
from scapy.all import *

class P4trade(Packet):
    name = "P4trade"
    fields_desc = [ StrFixedLenField("P", "P", length=1),
                    StrFixedLenField("Four", "4", length=1),
                    XByteField("version", 0x01),
                    IntField("act", 0),
                    IntField("amt", 0),
                    IntField("mktprice", 0),
                    IntField("cmpAvg", 0),
                    IntField("mAvgS", 0),
                    IntField("mAvgM", 0),
                    IntField("mAvgL", 0),
                    IntField("tc", 0)]

bind_layers(Ether, P4trade, type=0x1234)

class NumParseError(Exception):
    pass

class OpParseError(Exception):
    pass

class Token:
    def __init__(self,type,value = None):
        self.type = type
        self.value = value

def get_if():
    ifs=get_if_list()
    iface= "veth0-1" # "h1-eth0"
    #for i in get_if_list():
    #    if "eth0" in i:
    #        iface=i
    #        break;
    #if not iface:
    #    print("Cannot find eth0 interface")
    #    exit(1)
    #print(iface)
    return iface

def main():

    priceFile = open("TSLA_1min_open.csv", "r")
    priceData = priceFile.read()
    priceData = priceData.replace('\n', ' ').split()
    for i in range(len(priceData)):
        priceData[i] = int(float(priceData[i]))
    
    iface = "enx0c37965f8a25"
    accbal = 0
    sharesHeld = 0
    #for i in range(len(priceData)):
    for i in range(600):
        price = priceData[i]
        print("data point #" + str(i))
        print("market price " + str(price))

        try:
            pkt = Ether(dst='00:04:00:00:00:00', type=0x1234) / P4trade(mktprice=price)
            pkt = pkt/' '
            resp = srp1(pkt, iface=iface,timeout=5, verbose=False)
            if resp:
                p4trade=resp[P4trade]
                if p4trade:
                    if p4trade.act == 0:
                    	print("No trade advised")
                    elif p4trade.act == 1:
                    	print("BUY" + " " + str(p4trade.amt) + " shares")
                    	sharesHeld += p4trade.amt
                    	accbal -= price*p4trade.amt
                    elif p4trade.act == 2:
                    	print("SELL" + " " + str(p4trade.amt) + " shares")
                    	sharesHeld -= p4trade.amt
                    	accbal += price*p4trade.amt
                    
                    # print("trade count " + str(p4trade.tc))
                    # print("moving avg  " + str(p4trade.mAvg))
                    print("acct bal    " + str(accbal))
                    print("shares held " + str(sharesHeld) + "\n")
                else:
                    print("cannot find P4trade header in the packet")
            else:
                print("Didn't receive response")
        except Exception as error:
            print(error)
    print("end of data")
    if sharesHeld != 0:
        print("buying/selling remaining shares at last market price")
        accbal += sharesHeld*price
    
    print("final PnL " + str(accbal))
        

if __name__ == '__main__':
    main()


