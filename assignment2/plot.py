# !/usr/bin/python3
import numpy as np
import matplotlib.pyplot as plt

# parameters to modify
filename1="iperf_q4.txt"
filename2="iperf3_q2udp.txt"
label1='iperf'
label2='iperf3'
xlabel = 'bandwidth (Mbps)'
ylabel = 'percentage of packets lost (%)'
title='iperf3 Qu2 UDP'
fig_name='iperf3_q2.png'
#bins=10 #adjust the number of bins to your plot


t1 = np.loadtxt(filename1, delimiter=" ", dtype="float")
t2 = np.loadtxt(filename2, delimiter=" ", dtype="float")

plt.plot(t1[:,0], t1[:,1], label=label1)  # Plot some data on the (implicit) axes.
plt.plot(t2[:,0], t2[:,1], label=label2)
#Comment the line above and uncomment the line below to plot a CDF
#plt.hist(t, bins, density=True, histtype='step', cumulative=True, label=label)
plt.xlabel(xlabel)
plt.ylabel(ylabel)
plt.title(title)
plt.legend(loc='best')
plt.savefig(fig_name)
plt.show()
