import { StatusBar } from 'expo-status-bar';
import { StyleSheet, Text, View } from 'react-native';

export default function App() {
  return (
    <View style={styles.container}>
      <Text style={styles.title}>Listen SDR</Text>
      <Text style={styles.subtitle}>Live preview on iPhone from Windows</Text>
      <StatusBar style="auto" />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f3f6fa',
    alignItems: 'center',
    justifyContent: 'center',
  },
  title: {
    fontSize: 28,
    fontWeight: '700',
    color: '#0b1f3a',
  },
  subtitle: {
    marginTop: 8,
    fontSize: 14,
    color: '#3a4a63',
  },
});
