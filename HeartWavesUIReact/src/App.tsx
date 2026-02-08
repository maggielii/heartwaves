import { Routes, Route } from 'react-router-dom'
import Layout from './components/Layout'
import HomePage from './pages/HomePage'
import QuestionsPage from './pages/QuestionsPage'
import PdfReportPage from './pages/PdfReportPage'

function App() {
  return (
    <Routes>
      <Route element={<Layout />}>
        <Route path="/" element={<HomePage />} />
        <Route path="/questions" element={<QuestionsPage />} />
        <Route path="/report" element={<PdfReportPage />} />
      </Route>
    </Routes>
  )
}

export default App
