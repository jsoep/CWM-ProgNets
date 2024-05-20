# !/usr/bin/python3
import numpy as np
import matplotlib.pyplot as plt

# parameters to modify
filename1="iperf3_q1proc.txt"
#filename2="iperf_3sc.txt"
label1=''
#label2='server-client'
xlabel = 'time (s)'
ylabel = 'bandwidth (Mbps)'
title='iperf3 Qu1'
fig_name='iperf3_q1.png'
#bins=10 #adjust the number of bins to your plot


t1 = np.loadtxt(filename1, delimiter=" ", dtype="float")
#t2 = np.loadtxt(filename2, delimiter=" ", dtype="float")

plt.plot(t1[:,0], t1[:,1], label=label1)  # Plot some data on the (implicit) axes.
#plt.plot(t2[:,0], t2[:,1], label=label2)
#Comment the line above and uncomment the line below to plot a CDF
#plt.hist(t, bins, density=True, histtype='step', cumulative=True, label=label)
plt.xlabel(xlabel)
plt.ylabel(ylabel)
plt.title(title)
plt.legend(loc='best')
plt.savefig(fig_name)
plt.show()
